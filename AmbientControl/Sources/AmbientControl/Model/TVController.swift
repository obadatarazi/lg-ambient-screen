import Foundation
import Observation

/// Talks to the TV through LG's ares-cli (Developer Mode SSH).
@MainActor
@Observable
final class TVController {
    static let appID = "com.cupcoding.screensaver"

    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "tvDevice") }
    }
    var info: [String: String] = [:]
    var reachable: Bool? = nil
    var appRunning: Bool? = nil
    var busy: String? = nil
    var lastResult: String = ""
    var aresInstalled = Shell.which("ares-launch")

    init() {
        deviceName = UserDefaults.standard.string(forKey: "tvDevice") ?? "lg-tv"
    }

    var model: String { info["modelName"] ?? "LG TV" }

    func refresh() async {
        guard aresInstalled, busy == nil else { return }
        busy = "Checking TV…"
        defer { busy = nil }
        let r = await Shell.run(["ares-device", "-i", "-d", deviceName], timeout: 25)
        var parsed: [String: String] = [:]
        for line in r.output.split(separator: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, !kv[0].isEmpty, !kv[0].hasPrefix("[") { parsed[kv[0]] = kv[1] }
        }
        info = parsed
        reachable = r.ok && parsed["modelName"] != nil
        if reachable == true {
            let running = await Shell.run(["ares-launch", "-r", "-d", deviceName], timeout: 20)
            appRunning = running.output.contains(Self.appID)
        } else {
            appRunning = nil
            lastResult = "TV not reachable. Make sure it is on, on the same Wi-Fi, and Developer Mode is enabled."
        }
    }

    /// Launches (or relaunches) the TV app and tells it where this Mac's server is.
    func launch(server: String) async {
        let params = "{\"server\":\"\(server)\"}"
        await perform("Launching on TV…", ["ares-launch", "-d", deviceName, Self.appID, "-p", params],
                      success: "Ambient Screen is open on the TV.")
        if reachable != false { appRunning = true }
    }

    /// Opens any installed TV app with launch parameters (Developer Mode fallback).
    func launchApp(_ id: String, params: [String: Any]) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: params),
              let json = String(data: data, encoding: .utf8) else { return false }
        await perform("Opening on TV…", ["ares-launch", "-d", deviceName, id, "-p", json], success: "Opened on the TV.")
        return reachable != false && lastResult == "Opened on the TV."
    }

    func close() async {
        await perform("Closing…", ["ares-launch", "-d", deviceName, "-c", Self.appID],
                      success: "Closed on the TV.")
        appRunning = false
    }

    func install(ipk: URL) async {
        await perform("Installing on TV…", ["ares-install", "-d", deviceName, ipk.path],
                      success: "Installed the latest TV app.", timeout: 180)
    }

    private func perform(_ label: String, _ args: [String], success: String, timeout: TimeInterval = 40) async {
        guard aresInstalled else {
            lastResult = "ares-cli not found. Install it with: npm install -g @webos-tools/cli"
            return
        }
        busy = label
        defer { busy = nil }
        let r = await Shell.run(args, timeout: timeout)
        if r.ok {
            lastResult = success
            reachable = true
        } else {
            let line = r.output.split(separator: "\n").last { $0.contains("ERR!") || $0.contains("rror") }
            lastResult = line.map(String.init) ?? "The TV did not respond."
            if r.output.contains("timed out") || r.output.contains("EHOSTUNREACH") { reachable = false }
        }
    }
}
