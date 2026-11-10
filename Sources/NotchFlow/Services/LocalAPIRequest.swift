import Foundation

/// One HTTP/1.1 request read off a Local API connection.
struct LocalAPIRequest: Equatable {
    var method: String
    var path: String
    /// Header names are lowercased. A repeated header keeps its first value.
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var bodyText: String {
        String(decoding: body, as: UTF8.self)
    }
}

/// An HTTP error the Local API answers with before routing.
struct LocalAPIRejection: Equatable, Error {
    var status: Int
    var reason: String
    var message: String

    static let badRequest = LocalAPIRejection(status: 400, reason: "Bad Request", message: "bad request")
    static let tooLarge = LocalAPIRejection(status: 413, reason: "Payload Too Large", message: "request too large")
    static let headersTooLarge = LocalAPIRejection(
        status: 431,
        reason: "Request Header Fields Too Large",
        message: "headers too large"
    )
    static let chunkedNotSupported = LocalAPIRejection(
        status: 501,
        reason: "Not Implemented",
        message: "chunked bodies are not supported; send Content-Length"
    )
    static let crossOrigin = LocalAPIRejection(status: 403, reason: "Forbidden", message: "cross-origin requests are not allowed")
    static let badHost = LocalAPIRejection(status: 403, reason: "Forbidden", message: "host not allowed")
}

/// Pure parser for the Local API's tiny HTTP/1.1 subset. Bytes are fed in as they arrive;
/// the request is complete once the header block and `Content-Length` body bytes are in.
enum LocalAPIRequestParser {
    static let maxHeaderBytes = 16 * 1024
    static let maxRequestBytes = 1024 * 1024

    enum Outcome: Equatable {
        case needMoreData
        case complete(LocalAPIRequest)
        case rejected(LocalAPIRejection)
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> Outcome {
        if buffer.count > maxRequestBytes {
            return .rejected(.tooLarge)
        }
        guard let terminator = buffer.range(of: headerTerminator) else {
            return buffer.count > maxHeaderBytes ? .rejected(.headersTooLarge) : .needMoreData
        }
        let headerLength = terminator.lowerBound - buffer.startIndex
        if headerLength > maxHeaderBytes {
            return .rejected(.headersTooLarge)
        }
        guard let headerBlock = String(data: buffer[buffer.startIndex..<terminator.lowerBound], encoding: .utf8) else {
            return .rejected(.badRequest)
        }

        var lines = headerBlock.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              parts[1].hasPrefix("/"),
              parts[2].hasPrefix("HTTP/1.") else {
            return .rejected(.badRequest)
        }

        var headers: [String: String] = [:]
        var contentLength: Int?
        for line in lines {
            // Obsolete line folding and malformed lines are not accepted.
            guard let first = line.first, first != " ", first != "\t",
                  let colon = line.firstIndex(of: ":") else {
                return .rejected(.badRequest)
            }
            let name = line[..<colon].lowercased()
            guard !name.isEmpty, !name.contains(" ") else {
                return .rejected(.badRequest)
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" {
                guard let length = Int(value), length >= 0 else {
                    return .rejected(.badRequest)
                }
                if let contentLength, contentLength != length {
                    return .rejected(.badRequest)
                }
                contentLength = length
            }
            if headers[name] == nil {
                headers[name] = value
            }
        }

        if headers["transfer-encoding"] != nil {
            return .rejected(.chunkedNotSupported)
        }

        let bodyStart = terminator.upperBound
        let length = contentLength ?? 0
        guard length <= maxRequestBytes - (bodyStart - buffer.startIndex) else {
            return .rejected(.tooLarge)
        }
        guard buffer.endIndex - bodyStart >= length else {
            return .needMoreData
        }
        let body = Data(buffer[bodyStart..<(bodyStart + length)])
        return .complete(LocalAPIRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            body: body
        ))
    }

    /// Browsers attach `Origin`; DNS-rebinding pages also send their own `Host`.
    /// Neither may reach the API, even with a token.
    static func rejection(for request: LocalAPIRequest, port: UInt16?) -> LocalAPIRejection? {
        if request.header("origin") != nil {
            return .crossOrigin
        }
        guard let host = request.header("host") else {
            return .badHost
        }
        return isAllowedHost(host, port: port) ? nil : .badHost
    }

    static func isAllowedHost(_ raw: String, port: UInt16?) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let hostPart: Substring
        let portPart: Substring?
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return false }
            hostPart = value[value.startIndex...close]
            let rest = value[value.index(after: close)...]
            if rest.isEmpty {
                portPart = nil
            } else if rest.hasPrefix(":") {
                portPart = rest.dropFirst()
            } else {
                return false
            }
        } else if let colon = value.firstIndex(of: ":") {
            hostPart = value[..<colon]
            portPart = value[value.index(after: colon)...]
        } else {
            hostPart = Substring(value)
            portPart = nil
        }
        guard ["127.0.0.1", "localhost", "[::1]"].contains(String(hostPart)) else {
            return false
        }
        guard let portPart else { return true }
        guard let presented = UInt16(portPart), !portPart.isEmpty, portPart.allSatisfy(\.isNumber) else {
            return false
        }
        if let port, port != 0 {
            return presented == port
        }
        return true
    }
}
