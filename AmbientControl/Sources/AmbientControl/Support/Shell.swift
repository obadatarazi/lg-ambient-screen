import Foundation

/// Runs CLI tools (ares-cli is a set of Node scripts) with a PATH that includes Homebrew.
enum Shell {
    struct Result: Sendable {
        var ok: Bool
        var output: String
    }

    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func which(_ tool: String) -> Bool {
        searchPath.split(separator: ":").contains {
            FileManager.default.isExecutableFile(atPath: "\($0)/\(tool)")
        }
    }

    static func run(_ args: [String], timeout: TimeInterval = 30) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = searchPath
                p.environment = env
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: Result(ok: false, output: error.localizedDescription))
                    return
                }
                let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                timer.cancel()
                let out = String(data: data, encoding: .utf8) ?? ""
                cont.resume(returning: Result(ok: p.terminationStatus == 0 && !out.contains("ERR!"), output: out))
            }
        }
    }
}
