import Foundation

/// Thread-safe snapshot the HTTP server reads from its own queue.
/// The main-actor `AppModel` pushes new state into it whenever something changes.
final class SharedStore: @unchecked Sendable {
    let mediaDir: URL
    let tvAppDir: URL?
    let port: UInt16

    private let lock = NSLock()
    private var stateJSON = Data("{}".utf8)
    private var mediaJSON = Data("{\"items\":[]}".utf8)
    private var lanIP = "127.0.0.1"
    private var pollHandler: (@Sendable (String) -> Void)?

    init(mediaDir: URL, tvAppDir: URL?, port: UInt16) {
        self.mediaDir = mediaDir
        self.tvAppDir = tvAppDir
        self.port = port
    }

    func publish(state: TVState, library: [MediaItem], lanIP: String) {
        let enc = JSONEncoder()
        let s = (try? enc.encode(state)) ?? Data("{}".utf8)
        let m = (try? enc.encode(["items": library])) ?? Data("{\"items\":[]}".utf8)
        lock.lock()
        stateJSON = s
        mediaJSON = m
        self.lanIP = lanIP
        lock.unlock()
    }

    func setPollHandler(_ handler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        pollHandler = handler
        lock.unlock()
    }

    var state: Data { lock.lock(); defer { lock.unlock() }; return stateJSON }
    var media: Data { lock.lock(); defer { lock.unlock() }; return mediaJSON }

    var info: Data {
        lock.lock()
        let ip = lanIP
        lock.unlock()
        let obj: [String: Any] = ["name": "Ambient Control", "port": Int(port), "lanIp": ip]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    /// Called for every `/api/state` request that does not come from this Mac.
    func notePoll(from host: String) {
        lock.lock()
        let h = pollHandler
        lock.unlock()
        h?(host)
    }
}
