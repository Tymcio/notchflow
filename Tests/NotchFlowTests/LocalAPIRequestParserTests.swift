import Foundation
import XCTest
@testable import NotchFlow

final class LocalAPIRequestParserTests: XCTestCase {
    private func request(_ head: String, body: String = "") -> Data {
        Data((head.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n\r\n" + body).utf8)
    }

    private func complete(_ outcome: LocalAPIRequestParser.Outcome, file: StaticString = #filePath, line: UInt = #line) -> LocalAPIRequest? {
        guard case .complete(let request) = outcome else {
            XCTFail("expected a complete request, got \(outcome)", file: file, line: line)
            return nil
        }
        return request
    }

    func testParsesHeadersAndBody() throws {
        let body = #"{"text":"hi"}"#
        let data = request("""
        POST /v1/notes HTTP/1.1
        Host: 127.0.0.1:47800
        Authorization: Bearer abc
        Content-Type: application/json
        Content-Length: \(body.utf8.count)
        """, body: body)

        let parsed = try XCTUnwrap(complete(LocalAPIRequestParser.parse(data)))
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/v1/notes")
        XCTAssertEqual(parsed.header("Authorization"), "Bearer abc")
        XCTAssertEqual(parsed.bodyText, body)
    }

    func testWaitsForTheWholeBodyWhenItArrivesInPieces() throws {
        let body = String(repeating: "x", count: 100)
        let full = request("""
        POST /v1/agents/events HTTP/1.1
        Host: localhost
        Content-Length: 100
        """, body: body)

        // Headers only, then half the body: not done yet.
        let headerEnd = full.count - 100
        XCTAssertEqual(LocalAPIRequestParser.parse(full.prefix(10)), .needMoreData)
        XCTAssertEqual(LocalAPIRequestParser.parse(full.prefix(headerEnd)), .needMoreData)
        XCTAssertEqual(LocalAPIRequestParser.parse(full.prefix(headerEnd + 50)), .needMoreData)
        let parsed = try XCTUnwrap(complete(LocalAPIRequestParser.parse(full)))
        XCTAssertEqual(parsed.body.count, 100)
    }

    func testHeaderLookupIgnoresBodyLines() throws {
        let body = "Authorization: Bearer stolen"
        let data = request("""
        POST /v1/notes HTTP/1.1
        Host: 127.0.0.1
        Content-Length: \(body.utf8.count)
        """, body: body)
        let parsed = try XCTUnwrap(complete(LocalAPIRequestParser.parse(data)))
        XCTAssertNil(parsed.header("authorization"))
    }

    func testRejectsOversizedBodiesUpFront() {
        let data = request("""
        POST /v1/notes HTTP/1.1
        Host: 127.0.0.1
        Content-Length: \(LocalAPIRequestParser.maxRequestBytes + 1)
        """)
        XCTAssertEqual(LocalAPIRequestParser.parse(data), .rejected(.tooLarge))
    }

    func testRejectsEndlessHeaders() {
        let data = Data(("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: LocalAPIRequestParser.maxHeaderBytes + 1)).utf8)
        XCTAssertEqual(LocalAPIRequestParser.parse(data), .rejected(.headersTooLarge))
    }

    func testRejectsMalformedRequests() {
        XCTAssertEqual(LocalAPIRequestParser.parse(request("GARBAGE")), .rejected(.badRequest))
        XCTAssertEqual(LocalAPIRequestParser.parse(request("GET /v1/status HTTP/1.1\nno-colon-here")), .rejected(.badRequest))
        XCTAssertEqual(
            LocalAPIRequestParser.parse(request("POST /v1/notes HTTP/1.1\nContent-Length: -4")),
            .rejected(.badRequest)
        )
        XCTAssertEqual(
            LocalAPIRequestParser.parse(request("POST /v1/notes HTTP/1.1\nContent-Length: 3\nContent-Length: 4", body: "abcd")),
            .rejected(.badRequest)
        )
        XCTAssertEqual(
            LocalAPIRequestParser.parse(request("POST /v1/notes HTTP/1.1\nTransfer-Encoding: chunked")),
            .rejected(.chunkedNotSupported)
        )
    }

    func testRejectsBrowserOriginsAndForeignHosts() throws {
        let fromPage = try XCTUnwrap(complete(LocalAPIRequestParser.parse(request("""
        GET /v1/status HTTP/1.1
        Host: 127.0.0.1:47800
        Origin: https://evil.example
        """))))
        XCTAssertEqual(LocalAPIRequestParser.rejection(for: fromPage, port: 47800), .crossOrigin)

        let rebinding = try XCTUnwrap(complete(LocalAPIRequestParser.parse(request("""
        GET /v1/status HTTP/1.1
        Host: evil.example:47800
        """))))
        XCTAssertEqual(LocalAPIRequestParser.rejection(for: rebinding, port: 47800), .badHost)

        let noHost = try XCTUnwrap(complete(LocalAPIRequestParser.parse(request("GET /v1/status HTTP/1.1"))))
        XCTAssertNil(LocalAPIRequestParser.rejection(for: noHost, port: 47800))

        let local = try XCTUnwrap(complete(LocalAPIRequestParser.parse(request("""
        GET /v1/status HTTP/1.1
        Host: 127.0.0.1:47800
        """))))
        XCTAssertNil(LocalAPIRequestParser.rejection(for: local, port: 47800))
    }

    func testAllowedHosts() {
        XCTAssertTrue(LocalAPIRequestParser.isAllowedHost("127.0.0.1", port: 47800))
        XCTAssertTrue(LocalAPIRequestParser.isAllowedHost("localhost:47800", port: 47800))
        XCTAssertTrue(LocalAPIRequestParser.isAllowedHost("LOCALHOST:47800", port: 47800))
        XCTAssertTrue(LocalAPIRequestParser.isAllowedHost("[::1]:47800", port: 47800))
        XCTAssertTrue(LocalAPIRequestParser.isAllowedHost("127.0.0.1:1234", port: nil))
        XCTAssertFalse(LocalAPIRequestParser.isAllowedHost("127.0.0.1:1234", port: 47800))
        XCTAssertFalse(LocalAPIRequestParser.isAllowedHost("127.0.0.1:", port: 47800))
        XCTAssertFalse(LocalAPIRequestParser.isAllowedHost("127.0.0.1:abc", port: 47800))
        XCTAssertFalse(LocalAPIRequestParser.isAllowedHost("127.0.0.1.evil.example", port: 47800))
        XCTAssertFalse(LocalAPIRequestParser.isAllowedHost("localhost.evil.example:47800", port: 47800))
        XCTAssertFalse(LocalAPIRequestParser.isAllowedHost("0.0.0.0:47800", port: 47800))
    }
}
