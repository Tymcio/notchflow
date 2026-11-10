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

private struct LocalAPIAgentPermissionResponse: Encodable {
    let decision: String?
    let pending: Bool
}

private struct LocalAPIAgentQuestionResponse: Encodable {
    let answer: String?
    let pending: Bool
}

private struct LocalAPIAgentSessionResponse: Encodable {
    let id: String
    let agent: String
    let title: String
    let phase: String
    let detail: String
}

@MainActor
final class LocalAPIServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private weak var appState: AppState?
    private var activeConnections = 0

    /// A client must finish sending its request within this time.
    static let readTimeout: TimeInterval = 5
    /// Hook scripts poll once a second per pending prompt; this leaves plenty of room.
    static let maxConcurrentConnections = 16

    func start(appState: AppState) async throws {
        self.appState = appState
        // Demo mode has no hooks behind it and must not read the API token from the Keychain.
        guard !DemoMode.isEnabled, appState.settings.localAPIEnabled else { return }

        _ = try APIAuth.token()

        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        listener = try makeListener(using: params)
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor in
                await self.handle(connection: connection)
            }
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                if case .ready = state, let port = self.listener?.port?.rawValue {
                    self.port = port
                    self.persistConfig(port: port)
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
        guard activeConnections < Self.maxConcurrentConnections else {
            NotchFlowLog.api.info("Local API connection refused: too many open connections")
            connection.cancel()
            return
        }
        activeConnections += 1
        defer { activeConnections -= 1 }

        connection.start(queue: .main)
        // Slow or stalled clients are dropped instead of holding a slot forever.
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.readTimeout))
            if !Task.isCancelled { connection.cancel() }
        }
        let outcome = await readRequest(from: connection)
        timeout.cancel()

        let response: String
        switch outcome {
        case .complete(let request):
            if let rejection = LocalAPIRequestParser.rejection(for: request, port: port == 0 ? nil : port) {
                response = httpResponse(rejection)
            } else {
                response = await route(request: request)
            }
        case .rejected(let rejection):
            response = httpResponse(rejection)
        case .needMoreData:
            // Closed, timed out, or failed before a full request arrived.
            connection.cancel()
            return
        }

        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Reads until the headers and `Content-Length` body bytes are in, or the parser rejects.
    private func readRequest(from connection: NWConnection) async -> LocalAPIRequestParser.Outcome {
        var buffer = Data()
        while true {
            let chunk = await receiveChunk(from: connection)
            if let data = chunk.data, !data.isEmpty {
                buffer.append(data)
                let outcome = LocalAPIRequestParser.parse(buffer)
                if case .needMoreData = outcome {} else { return outcome }
            }
            if chunk.isComplete || chunk.failed {
                return .needMoreData
            }
        }
    }

    private struct ReceivedChunk {
        var data: Data?
        var isComplete: Bool
        var failed: Bool
    }

    private func receiveChunk(from connection: NWConnection) async -> ReceivedChunk {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                continuation.resume(returning: ReceivedChunk(data: data, isComplete: isComplete, failed: error != nil))
            }
        }
    }

    private func route(request: LocalAPIRequest) async -> String {
        let method = request.method
        let path = request.path

        guard APIAuth.validate(request.header("authorization")) else {
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

        case ("POST", "/v1/agents/events"):
            guard appState.hasAgentsAddon else {
                return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "agents addon required")))
            }
            guard let payload = parseJSONObject(request.bodyText) else {
                return invalidBody()
            }
            appState.agentSessionManager.ingestEvent(payload)
            appState.notifyAgentActivityChange()
            if appState.agentSessionManager.attentionCount > 0 {
                AppController.appDelegate?.showIsland()
                appState.activeModule = .agents
            }
            return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))

        case ("GET", "/v1/agents/sessions"):
            guard appState.hasAgentsAddon else {
                return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "agents addon required")))
            }
            let sessions = appState.agentSessionManager.sessions.map {
                LocalAPIAgentSessionResponse(
                    id: $0.id,
                    agent: $0.agent.rawValue,
                    title: $0.title,
                    phase: $0.phase.rawValue,
                    detail: $0.detail
                )
            }
            return httpResponse(status: 200, reason: "OK", body: encode(sessions))

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
            guard let text = extractJSONValue(request.bodyText, key: "text") else {
                return invalidBody()
            }
            do {
                try appState.notesManager.append(text: text, isPremium: appState.isPremium)
                appState.notes = appState.notesManager.notes
            } catch {
                NotchFlowLog.api.error("Failed to append note via API: \(error.localizedDescription, privacy: .public)")
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
            if method == "GET", path.hasPrefix("/v1/agents/permission/") {
                guard appState.hasAgentsAddon else {
                    return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "agents addon required")))
                }
                let id = String(path.dropFirst("/v1/agents/permission/".count))
                let decision = appState.agentSessionManager.permissionDecision(id: id)
                return httpResponse(
                    status: 200,
                    reason: "OK",
                    body: encode(LocalAPIAgentPermissionResponse(decision: decision?.rawValue, pending: decision == nil))
                )
            }
            if method == "POST", path.hasPrefix("/v1/agents/permission/") {
                guard appState.hasAgentsAddon else {
                    return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "agents addon required")))
                }
                let id = String(path.dropFirst("/v1/agents/permission/".count))
                guard let raw = extractJSONValue(request.bodyText, key: "decision"),
                      let decision = AgentPermissionDecision(rawValue: raw) else {
                    return invalidBody()
                }
                appState.agentSessionManager.decidePermission(id: id, decision: decision)
                appState.notifyAgentActivityChange()
                return httpResponse(status: 200, reason: "OK", body: encode(LocalAPIOKResponse(ok: true)))
            }
            if method == "GET", path.hasPrefix("/v1/agents/question/") {
                guard appState.hasAgentsAddon else {
                    return httpResponse(status: 403, reason: "Forbidden", body: encode(LocalAPIErrorResponse(error: "agents addon required")))
                }
                let id = String(path.dropFirst("/v1/agents/question/".count))
                let answer = appState.agentSessionManager.questionAnswer(id: id)
                return httpResponse(
                    status: 200,
                    reason: "OK",
                    body: encode(LocalAPIAgentQuestionResponse(answer: answer, pending: answer == nil))
                )
            }
            return httpResponse(status: 404, reason: "Not Found", body: encode(LocalAPIErrorResponse(error: "not found")))
        }
    }

    private func httpResponse(_ rejection: LocalAPIRejection) -> String {
        httpResponse(status: rejection.status, reason: rejection.reason, body: encode(LocalAPIErrorResponse(error: rejection.message)))
    }

    private func invalidBody() -> String {
        httpResponse(status: 400, reason: "Bad Request", body: encode(LocalAPIErrorResponse(error: "invalid JSON body")))
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

    private func parseJSONObject(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
