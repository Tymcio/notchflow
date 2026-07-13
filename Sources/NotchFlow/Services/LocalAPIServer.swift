import Foundation
import Network

struct LocalAPIConfig: Codable {
    let port: UInt16
    let baseURL: String
}

private struct LocalAPIStatusResponse: Encodable {
    let playing: Bool
    let title: String
    let premium: Bool
    let islandVisible: Bool
}

private struct LocalAPINoteResponse: Encodable {
    let text: String
}

private struct LocalAPIClipboardItemResponse: Encodable {
    let value: String
}

private struct LocalAPIOKResponse: Encodable {
    let ok: Bool
}

private struct LocalAPIErrorResponse: Encodable {
    let error: String
}

@MainActor
final class LocalAPIServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private weak var appState: AppState?

    func start(appState: AppState) async throws {
        self.appState = appState
        guard appState.settings.localAPIEnabled else { return }

        _ = try APIAuth.token()

        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        listener = try makeListener(using: params)
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

    private func makeListener(using params: NWParameters) throws -> NWListener {
        for port in preferredPorts() {
            guard let endpoint = NWEndpoint.Port(rawValue: port) else { continue }
            do {
                let listener = try NWListener(using: params, on: endpoint)
                NotchFlowLog.api.info("Local API listening on port \(port, privacy: .public)")
                return listener
            } catch {
                NotchFlowLog.api.debug("Port \(port, privacy: .public) unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        NotchFlowLog.api.warning("Using ephemeral local API port")
        return try NWListener(using: params, on: .any)
    }

    private func preferredPorts() -> [UInt16] {
        var ports: [UInt16] = []

        if let saved = Self.loadSavedPort() {
            ports.append(saved)
        }

        let defaultsPort = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
        if defaultsPort > 0, defaultsPort <= Int(UInt16.max) {
            ports.append(UInt16(defaultsPort))
        }

        ports.append(NotchFlowConstants.localAPIPort)

        var seen = Set<UInt16>()
        return ports.filter { seen.insert($0).inserted }
    }

    private static let portDefaultsKey = "localAPIPort"

    private static func loadSavedPort() -> UInt16? {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/api.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LocalAPIConfig.self, from: data),
              config.port > 0 else {
            return nil
        }
        return config.port
    }

    private func persistConfig(port: UInt16) {
        UserDefaults.standard.set(Int(port), forKey: Self.portDefaultsKey)
        let config = LocalAPIConfig(port: port, baseURL: "http://127.0.0.1:\(port)")
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/api.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try SecureFileWriter.write(data, to: url)
        } catch {
            NotchFlowLog.api.error("Failed to persist API config: \(error.localizedDescription, privacy: .public)")
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
        guard let requestLine = lines.first else {
            return httpResponse(status: 400, reason: "Bad Request", body: encode(LocalAPIErrorResponse(error: "bad request")))
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, reason: "Bad Request", body: encode(LocalAPIErrorResponse(error: "bad request")))
        }

        let method = String(parts[0])
        let path = String(parts[1])

        let authLine = lines.first { $0.lowercased().hasPrefix("authorization:") }
        let authValue = authLine?.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
        guard APIAuth.validate(authValue) else {
            return httpResponse(status: 401, reason: "Unauthorized", body: encode(LocalAPIErrorResponse(error: "unauthorized")))
        }

        guard let appState else {
            return httpResponse(status: 503, reason: "Service Unavailable", body: encode(LocalAPIErrorResponse(error: "unavailable")))
        }

        switch (method, path) {
        case ("GET", "/v1/status"):
            let body = encode(LocalAPIStatusResponse(
                playing: appState.mediaState.isPlaying,
                title: appState.mediaState.title,
                premium: appState.isPremium,
                islandVisible: AppController.panelController?.isIslandVisible ?? false
            ))
            return httpResponse(status: 200, reason: "OK", body: body)

        case ("POST", "/v1/media/play-pause"):
            appState.mediaMonitor.togglePlayPause()
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        case ("POST", "/v1/media/next"):
            appState.mediaMonitor.nextTrack()
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        case ("POST", "/v1/media/previous"):
            appState.mediaMonitor.previousTrack()
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        case ("GET", "/v1/notes"):
            guard appState.isPremium else {
                return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "premium required")))
            }
            let notes = appState.notesManager.visibleNotes(isPremium: true)
                .map { LocalAPINoteResponse(text: $0.text) }
            return httpResponse(status: 200, reason: "OK", body: encode(notes))

        case ("POST", "/v1/notes"):
            guard appState.isPremium else {
                return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "premium required")))
            }
            if let bodyStart = request.range(of: "\r\n\r\n") {
                let body = String(request[bodyStart.upperBound...])
                if let text = extractJSONValue(body, key: "text") {
                    do {
                        try appState.notesManager.append(text: text, isPremium: appState.isPremium)
                        appState.notes = appState.notesManager.notes
                    } catch {
                        NotchFlowLog.api.error("Failed to append note via API: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        case ("GET", "/v1/clipboard"):
            guard appState.isPremium else {
                return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "premium required")))
            }
            let items = appState.clipboardManager.visibleEntries(isPremium: appState.isPremium)
                .map { LocalAPIClipboardItemResponse(value: $0.value) }
            return httpResponse(status: 200, reason: "OK", body: encode(items))

        case ("POST", "/v1/island/show"):
            AppController.appDelegate?.showIsland()
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        case ("POST", "/v1/mirror/toggle"):
            guard appState.isPremium else {
                return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "premium required")))
            }
            if appState.cameraMirrorManager.isActive {
                appState.cameraMirrorManager.stopPreview()
            } else {
                guard MirrorActivation.confirmStart() else {
                    return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "mirror denied")))
                }
                await appState.cameraMirrorManager.startPreview()
            }
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        default:
            return httpResponse(status: 404, reason: "Not Found", body: encode(LocalAPIErrorResponse(error: "not found")))
        }
    }

    private func httpResponse(status: Int, reason: String, body: String) -> String {
        "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"error":"encoding failed"}"#
        }
        return json
    }

    private func extractJSONValue(_ body: String, key: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[key] as? String else { return nil }
        return value
    }
}
