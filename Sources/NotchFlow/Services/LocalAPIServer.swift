import Foundation
import Network

struct LocalAPIConfig: Codable {
    let port: UInt16
    let baseURL: String
}

@MainActor
final class LocalAPIServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private weak var appState: AppState?

    func start(appState: AppState) async throws {
        self.appState = appState
        guard appState.settings.localAPIEnabled else { return }

        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: .any)
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                await self?.handle(connection: connection)
            }
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state, let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    self?.persistConfig(port: port)
                }
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func persistConfig(port: UInt16) {
        let config = LocalAPIConfig(port: port, baseURL: "http://127.0.0.1:\(port)")
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/api.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func handle(connection: NWConnection) async {
        connection.start(queue: .main)
        let data = await receive(connection: connection)
        guard let data, let request = String(data: data, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let response = await route(request: request)
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func receive(connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func route(request: String) async -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return httpResponse(status: 400, body: #"{"error":"bad request"}"#) }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return httpResponse(status: 400, body: #"{"error":"bad request"}"#) }

        let method = String(parts[0])
        let path = String(parts[1])

        let authLine = lines.first { $0.lowercased().hasPrefix("authorization:") }
        let authValue = authLine?.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
        guard APIAuth.validate(authValue) else {
            return httpResponse(status: 401, body: #"{"error":"unauthorized"}"#)
        }

        guard let appState else {
            return httpResponse(status: 503, body: #"{"error":"unavailable"}"#)
        }

        switch (method, path) {
        case ("GET", "/v1/status"):
            let body = """
            {"playing":\(appState.mediaState.isPlaying),"title":"\(escape(appState.mediaState.title))","premium":\(appState.isPremium),"islandVisible":\(AppController.appDelegate != nil)}
            """
            return httpResponse(status: 200, body: body)

        case ("POST", "/v1/media/play-pause"):
            appState.mediaMonitor.togglePlayPause()
            return httpResponse(status: 200, body: #"{"ok":true}"#)

        case ("POST", "/v1/media/next"):
            appState.mediaMonitor.nextTrack()
            return httpResponse(status: 200, body: #"{"ok":true}"#)

        case ("POST", "/v1/media/previous"):
            appState.mediaMonitor.previousTrack()
            return httpResponse(status: 200, body: #"{"ok":true}"#)

        case ("GET", "/v1/notes"):
            let notes = appState.notesManager.notes.map { "{\"text\":\"\(escape($0.text))\"}" }.joined(separator: ",")
            return httpResponse(status: 200, body: "[\(notes)]")

        case ("POST", "/v1/notes"):
            if let bodyStart = request.range(of: "\r\n\r\n") {
                let body = String(request[bodyStart.upperBound...])
                if let text = extractJSONValue(body, key: "text") {
                    try? appState.notesManager.append(text: text, isPremium: appState.isPremium)
                    appState.notes = appState.notesManager.notes
                }
            }
            return httpResponse(status: 200, body: #"{"ok":true}"#)

        case ("GET", "/v1/clipboard"):
            let items = appState.clipboardManager.visibleEntries(isPremium: appState.isPremium)
                .map { "{\"value\":\"\(escape($0.value))\"}" }
                .joined(separator: ",")
            return httpResponse(status: 200, body: "[\(items)]")

        case ("POST", "/v1/island/show"):
            AppController.appDelegate?.showIsland()
            return httpResponse(status: 200, body: #"{"ok":true}"#)

        case ("POST", "/v1/mirror/toggle"):
            if appState.cameraMirrorManager.isActive {
                appState.cameraMirrorManager.stopPreview()
            } else {
                await appState.cameraMirrorManager.startPreview()
            }
            return httpResponse(status: 200, body: #"{"ok":true}"#)

        default:
            return httpResponse(status: 404, body: #"{"error":"not found"}"#)
        }
    }

    private func httpResponse(status: Int, body: String) -> String {
        "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func extractJSONValue(_ body: String, key: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[key] as? String else { return nil }
        return value
    }
}
