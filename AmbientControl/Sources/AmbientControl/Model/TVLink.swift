import Foundation
import Observation

/// Direct Wi-Fi control of the TV through LG's built-in remote API (SSAP, WebSocket on port 3000),
/// the same channel LG's phone app uses. Needs a one-time "Allow" on the TV; no Developer Mode,
/// no server. Settings are delivered as launch parameters, which a running app receives as a
/// `webOSRelaunch` event.
@MainActor
@Observable
final class TVLink {
    enum Status: Equatable {
        case idle, connecting, waitingForApproval, ready
        case failed(String)
    }

    var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "tvHost") }
    }
    private(set) var clientKey: String? {
        didSet { UserDefaults.standard.set(clientKey, forKey: "tvClientKey") }
    }
    private(set) var status: Status = .idle
    private(set) var searching = false

    var paired: Bool { clientKey != nil }
    var ready: Bool { status == .ready }

    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var waiters: [String: CheckedContinuation<[String: Any], Error>] = [:]
    @ObservationIgnored private var registerID: String?
    @ObservationIgnored private var nextID = 0

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        clientKey = UserDefaults.standard.string(forKey: "tvClientKey")
    }

    // MARK: - Public API

    /// Connects quietly with the saved key. With `allowPrompt`, asks the TV to show
    /// the pairing prompt and waits up to a minute for the user to accept.
    @discardableResult
    func connect(allowPrompt: Bool = false) async -> Bool {
        if ready, socket != nil { return true }
        guard !host.isEmpty, allowPrompt || paired,
              let url = URL(string: "ws://\(host):3000") else { return false }

        status = .connecting
        let ws = URLSession.shared.webSocketTask(with: url)
        socket = ws
        ws.resume()
        listen(ws)

        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "appId": "com.cupcoding.ambientcontrol",
                "vendorId": "com.cupcoding",
                "localizedAppNames": ["": "Ambient Control"],
                "permissions": ["LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "READ_RUNNING_APPS",
                                "READ_INSTALLED_APPS", "READ_APP_STATUS", "READ_CURRENT_CHANNEL",
                                "WRITE_NOTIFICATION_TOAST"]
            ] as [String: Any]
        ]
        if let key = clientKey { payload["client-key"] = key }

        do {
            let id = makeID()
            registerID = id
            let reply = try await send(["type": "register", "id": id, "payload": payload],
                                       id: id, timeout: allowPrompt ? 60 : 8)
            if let key = reply["client-key"] as? String { clientKey = key }
            status = .ready
            return true
        } catch {
            drop(reason: (error as? LinkError)?.message ?? error.localizedDescription)
            return false
        }
    }

    func forget() {
        clientKey = nil
        drop(reason: nil)
    }

    /// The app currently shown on the TV, or nil if unknown.
    func foregroundApp() async -> String? {
        guard await connect() else { return nil }
        let r = try? await request("ssap://com.webos.applicationManager/getForegroundAppInfo")
        return r?["appId"] as? String
    }

    /// Launches the app, or delivers `params` to it as a relaunch if it is already open.
    func launch(_ appID: String, params: [String: Any]) async -> Bool {
        guard await connect() else { return false }
        let r = try? await request("ssap://system.launcher/launch", payload: ["id": appID, "params": params])
        return (r?["returnValue"] as? Bool) ?? (r != nil)
    }

    func turnOff() async -> Bool {
        guard await connect() else { return false }
        let r = try? await request("ssap://system/turnOff")
        return (r?["returnValue"] as? Bool) ?? (r != nil)
    }

    /// A native webOS toast, shown over whatever app is on screen.
    func toast(_ message: String) async -> Bool {
        guard await connect() else { return false }
        let r = try? await request("ssap://system.notifications/createToast", payload: ["message": message])
        return r != nil
    }

    /// Finds the TV on the local network: tries the saved address, then scans the subnet
    /// for LG's remote API (port 3000 answers "Hello world").
    func discover(subnetOf lanIP: String) async {
        searching = true
        defer { searching = false }
        if !host.isEmpty, await Self.isLGRemote(host) { return }
        let parts = lanIP.split(separator: ".")
        guard parts.count == 4 else { return }
        let prefix = parts.prefix(3).joined(separator: ".")
        let found = await withTaskGroup(of: String?.self) { group -> String? in
            for i in 1...254 where "\(prefix).\(i)" != lanIP {
                let ip = "\(prefix).\(i)"
                group.addTask { await Self.isLGRemote(ip) ? ip : nil }
            }
            for await ip in group {
                if let ip {
                    group.cancelAll()
                    return ip
                }
            }
            return nil
        }
        if let found { host = found }
    }

    // MARK: - SSAP plumbing

    private struct LinkError: Error {
        let message: String
    }

    private func makeID() -> String {
        nextID += 1
        return "ac\(nextID)"
    }

    private func request(_ uri: String, payload: [String: Any] = [:]) async throws -> [String: Any] {
        let id = makeID()
        return try await send(["type": "request", "id": id, "uri": uri, "payload": payload], id: id, timeout: 10)
    }

    private func send(_ message: [String: Any], id: String, timeout: TimeInterval) async throws -> [String: Any] {
        guard let ws = socket,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { throw LinkError(message: "Not connected") }
        return try await withCheckedThrowingContinuation { cont in
            waiters[id] = cont
            ws.send(.string(text)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.finish(id, .failure(LinkError(message: error.localizedDescription))) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(id, .failure(LinkError(message: "The TV did not answer")))
            }
        }
    }

    private func finish(_ id: String, _ result: Result<[String: Any], Error>) {
        guard let cont = waiters.removeValue(forKey: id) else { return }
        cont.resume(with: result)
    }

    private func listen(_ ws: URLSessionWebSocketTask) {
        ws.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === ws else { return }
                switch result {
                case .success(let message):
                    if case let .string(text) = message { self.handle(text) }
                    self.listen(ws)
                case .failure:
                    self.drop(reason: self.status == .ready ? nil : "Could not reach the TV")
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = msg["id"] as? String else { return }
        let type = msg["type"] as? String ?? ""
        let payload = msg["payload"] as? [String: Any] ?? [:]

        if type == "error" {
            finish(id, .failure(LinkError(message: msg["error"] as? String ?? "TV error")))
        } else if id == registerID {
            if type == "registered" {
                finish(id, .success(payload))
            } else if payload["pairingType"] as? String == "PROMPT" {
                status = .waitingForApproval
            }
        } else if type == "response" {
            finish(id, .success(payload))
        }
    }

    private func drop(reason: String?) {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        for (id, _) in waiters { finish(id, .failure(LinkError(message: "Disconnected"))) }
        status = reason.map { .failed($0) } ?? .idle
    }

    nonisolated private static func isLGRemote(_ ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip):3000/") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.2
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return false }
        return String(data: data, encoding: .utf8)?.contains("Hello world") == true
    }
}
