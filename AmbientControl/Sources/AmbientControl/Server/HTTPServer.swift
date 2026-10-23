import Foundation
import Network

/// Minimal HTTP/1.1 server (GET/HEAD/OPTIONS) built on Network.framework.
/// Serves the TV state API, the media library (with Range support for video),
/// and the TV app itself under /tv/ for the live preview.
final class HTTPServer: @unchecked Sendable {
    private let store: SharedStore
    private let queue = DispatchQueue(label: "ambient.http", attributes: .concurrent)
    private var listener: NWListener?

    init(store: SharedStore) {
        self.store = store
    }

    func start(onState: @escaping @Sendable (String?) -> Void) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: store.port)!)
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: onState(nil)
            case .failed(let err): onState("Server failed: \(err.localizedDescription)")
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let req = Request(buf) {
                self.route(req, conn)
            } else if done || error != nil || buf.count > 256 * 1024 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let query: String
        let headers: [String: String]

        init?(_ data: Data) {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
            let lines = head.components(separatedBy: "\r\n")
            let parts = lines[0].split(separator: " ")
            guard parts.count >= 2 else { return nil }
            method = String(parts[0])
            let target = String(parts[1])
            let pieces = target.split(separator: "?", maxSplits: 1)
            path = String(pieces[0]).removingPercentEncoding ?? String(pieces[0])
            query = pieces.count > 1 ? String(pieces[1]) : ""
            var h: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let i = line.firstIndex(of: ":") else { continue }
                h[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            headers = h
        }
    }

    private func route(_ req: Request, _ conn: NWConnection) {
        if req.method == "OPTIONS" {
            send(conn, status: "204 No Content", type: nil, body: Data())
            return
        }
        guard req.method == "GET" || req.method == "HEAD" else {
            send(conn, status: "405 Method Not Allowed", type: "text/plain", body: Data("method not allowed".utf8))
            return
        }
        let head = req.method == "HEAD"

        switch req.path {
        case "/api/state":
            if case let .hostPort(host, _) = conn.endpoint {
                let h = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                if h != "127.0.0.1" && h != "::1" { store.notePoll(from: h) }
            }
            send(conn, status: "200 OK", type: "application/json", body: store.state, head: head)
        case "/api/media":
            send(conn, status: "200 OK", type: "application/json", body: store.media, head: head)
        case "/api/info":
            send(conn, status: "200 OK", type: "application/json", body: store.info, head: head)
        case "/", "/tv", "/tv/":
            redirect(conn, to: "/tv/index.html")
        case "/screen/init.mp4":
            if let data = SegmentHub.shared.initData {
                sendScreen(conn, data: data, seq: 0)
            } else {
                notFound(conn)
            }
        case "/screen/seg":
            let q = Dictionary(req.query.split(separator: "&").compactMap { pair -> (String, String)? in
                let kv = pair.split(separator: "=", maxSplits: 1)
                return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
            }, uniquingKeysWith: { a, _ in a })
            let after = Int(q["after"] ?? "") ?? 0
            if let dl = Int(q["dl"] ?? ""), let size = Int(q["sz"] ?? "") {
                SegmentHub.shared.report(downloadMs: dl, bytes: size, jumps: Int(q["j"] ?? "") ?? 0)
            }
            SegmentHub.shared.next(after: after, timeout: 5) { [weak self] data, seq in
                guard let self else { return }
                if let data {
                    self.sendScreen(conn, data: data, seq: seq)
                } else if seq < 0 {
                    self.notFound(conn)  // sharing stopped
                } else {
                    self.send(conn, status: "204 No Content", type: nil, body: Data())
                }
            }
        default:
            if req.path.hasPrefix("/yt/") {
                serveYouTube(req, conn)
                return
            }
            if req.path.hasPrefix("/media/") {
                serveFile(base: store.mediaDir, rel: String(req.path.dropFirst("/media/".count)), req: req, conn: conn)
            } else if req.path.hasPrefix("/tv/"), let dir = store.tvAppDir {
                serveFile(base: dir, rel: String(req.path.dropFirst("/tv/".count)), req: req, conn: conn)
            } else {
                notFound(conn)
            }
        }
    }

    // MARK: - Responses

    private func header(status: String, type: String?, length: Int, extra: [String: String] = [:]) -> Data {
        var s = "HTTP/1.1 \(status)\r\n"
        s += "Access-Control-Allow-Origin: *\r\n"
        s += "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n"
        s += "Access-Control-Allow-Headers: Content-Type, Accept, Range\r\n"
        s += "Cache-Control: no-store\r\n"
        s += "Connection: close\r\n"
        if let type { s += "Content-Type: \(type)\r\n" }
        s += "Content-Length: \(length)\r\n"
        for (k, v) in extra { s += "\(k): \(v)\r\n" }
        s += "\r\n"
        return Data(s.utf8)
    }

    private func send(_ conn: NWConnection, status: String, type: String?, body: Data, head: Bool = false) {
        var out = header(status: status, type: type, length: body.count)
        if !head { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func redirect(_ conn: NWConnection, to location: String) {
        let out = header(status: "302 Found", type: nil, length: 0, extra: ["Location": location])
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func notFound(_ conn: NWConnection) {
        send(conn, status: "404 Not Found", type: "application/json", body: Data("{\"error\":\"not found\"}".utf8))
    }

    /// Serves a file below `base`, rejecting any path that escapes it.
    private func serveFile(base: URL, rel: String, req: Request, conn: NWConnection) {
        let comps = rel.split(separator: "/").map(String.init)
        guard !comps.isEmpty, !comps.contains(where: { $0 == ".." || $0.isEmpty }) else {
            notFound(conn)
            return
        }
        let url = comps.reduce(base) { $0.appendingPathComponent($1) }
        guard url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = (attrs[.size] as? NSNumber)?.intValue,
              let handle = try? FileHandle(forReadingFrom: url) else {
            notFound(conn)
            return
        }

        var start = 0
        var end = size - 1
        var status = "200 OK"
        var extra = ["Accept-Ranges": "bytes"]
        if let range = req.headers["range"], range.hasPrefix("bytes="), size > 0 {
            let spec = range.dropFirst(6).split(separator: ",")[0]
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
            if bounds.count == 2 {
                if bounds[0].isEmpty, let suffix = Int(bounds[1]) {
                    start = max(0, size - suffix)
                } else {
                    start = Int(bounds[0]) ?? 0
                    if let e = Int(bounds[1]) { end = min(e, size - 1) }
                }
                // Cap open-ended ranges so the TV's player streams in pieces.
                end = min(end, start + 8 * 1024 * 1024 - 1)
                guard start <= end else {
                    try? handle.close()
                    send(conn, status: "416 Range Not Satisfiable", type: nil, body: Data())
                    return
                }
                status = "206 Partial Content"
                extra["Content-Range"] = "bytes \(start)-\(end)/\(size)"
            }
        }
        let length = max(0, end - start + 1)
        let head = header(status: status, type: Self.mime(for: url.pathExtension), length: length, extra: extra)
        conn.send(content: head, completion: .contentProcessed { [weak self] err in
            guard err == nil, req.method != "HEAD", length > 0 else {
                try? handle.close()
                conn.cancel()
                return
            }
            try? handle.seek(toOffset: UInt64(start))
            self?.stream(handle, remaining: length, conn: conn)
        })
    }

    private func stream(_ handle: FileHandle, remaining: Int, conn: NWConnection) {
        let chunk = (try? handle.read(upToCount: min(remaining, 512 * 1024))) ?? Data()
        if chunk.isEmpty {
            try? handle.close()
            conn.cancel()
            return
        }
        let left = remaining - chunk.count
        conn.send(content: chunk, completion: .contentProcessed { [weak self] err in
            if err != nil || left <= 0 {
                try? handle.close()
                conn.cancel()
            } else {
                self?.stream(handle, remaining: left, conn: conn)
            }
        })
    }

    // MARK: - YouTube (fragmented MP4, video on demand)

    /// `/yt/<key>/init.mp4` and `/yt/<key>/seg?n=N`. A segment that is still downloading
    /// is long-polled (up to ~8 s); `X-End: 1` tells the TV the video is complete.
    private func serveYouTube(_ req: Request, _ conn: NWConnection) {
        let parts = req.path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[1].range(of: "^[A-Za-z0-9_-]{11}-[0-9]{3,4}$", options: .regularExpression) != nil else {
            notFound(conn)
            return
        }
        let key = parts[1]
        if parts[2] == "init.mp4" {
            if let data = YouTubeStreamer.shared.initSegment(key: key) {
                sendScreen(conn, data: data, seq: 0)
            } else {
                notFound(conn)
            }
            return
        }
        guard parts[2] == "seg",
              let n = Int(req.query.split(separator: "&").first { $0.hasPrefix("n=") }?.dropFirst(2) ?? "") else {
            notFound(conn)
            return
        }
        waitForSegment(key: key, n: n, deadline: Date().addingTimeInterval(8), conn: conn)
    }

    private func waitForSegment(key: String, n: Int, deadline: Date, conn: NWConnection) {
        switch YouTubeStreamer.shared.segment(key: key, n: n) {
        case .data(let data):
            sendScreen(conn, data: data, seq: n)
        case .end:
            let out = header(status: "204 No Content", type: nil, length: 0,
                             extra: ["X-End": "1", "Access-Control-Expose-Headers": "X-Seq, X-End"])
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        case .missing:
            notFound(conn)
        case .notYet:
            if Date() > deadline {
                send(conn, status: "204 No Content", type: nil, body: Data())
            } else {
                queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.waitForSegment(key: key, n: n, deadline: deadline, conn: conn)
                }
            }
        }
    }

    // MARK: - Screen share (fragmented MP4)

    private func sendScreen(_ conn: NWConnection, data: Data, seq: Int) {
        var out = header(status: "200 OK", type: "video/mp4", length: data.count,
                         extra: ["X-Seq": "\(seq)", "Access-Control-Expose-Headers": "X-Seq, X-End"])
        out.append(data)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
}
