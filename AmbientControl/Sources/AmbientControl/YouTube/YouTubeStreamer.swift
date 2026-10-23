import Foundation

/// Plays YouTube videos inside Ambient on the TV (picture + TV speakers), no app switching.
///
/// yt-dlp resolves the H.264 + AAC streams, ffmpeg remuxes them (no re-encode) into
/// fragmented-MP4 HLS segments as they download, and the TV starts playing after the first
/// segments arrive via Media Source Extensions. Finished videos stay cached for instant replay.
final class YouTubeStreamer: @unchecked Sendable {
    static let shared = YouTubeStreamer()

    enum Quality: Int, CaseIterable, Identifiable {
        case p480 = 480, p720 = 720, p1080 = 1080
        var id: Int { rawValue }
        var label: String { "\(rawValue)p" }
    }

    struct Prepared: Sendable {
        let id: String
        let title: String
    }

    struct StreamError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let lock = NSLock()
    private var jobs: [String: Process] = [:]
    /// Lookups in progress, so a prefetch (on paste) and Play share the same work.
    private var inflight: [String: Task<Prepared, Error>] = [:]
    private(set) var root: URL = FileManager.default.temporaryDirectory

    func configure(cacheDir: URL) {
        root = cacheDir
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func dir(_ id: String, _ q: Quality) -> URL { root.appendingPathComponent("\(id)-\(q.rawValue)") }

    /// Starts (or reuses) the download and returns once playback can begin.
    func prepare(id: String, quality: Quality) async throws -> Prepared {
        let key = "\(id)-\(quality.rawValue)"
        let task = sharedTask(key) { try await self.start(id: id, quality: quality) }
        do {
            let result = try await task.value
            finishTask(key)
            return result
        } catch {
            finishTask(key)
            throw error
        }
    }

    private func sharedTask(_ key: String, _ make: @escaping @Sendable () async throws -> Prepared) -> Task<Prepared, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let t = inflight[key] { return t }
        let t = Task { try await make() }
        inflight[key] = t
        return t
    }

    private func finishTask(_ key: String) {
        lock.lock()
        inflight[key] = nil
        lock.unlock()
    }

    private func register(_ key: String, _ p: Process) {
        lock.lock()
        jobs[key] = p
        lock.unlock()
    }

    private func start(id: String, quality: Quality) async throws -> Prepared {
        let d = dir(id, quality)
        let titleFile = d.appendingPathComponent("title.txt")
        if isComplete(d) || isRunning(id, quality) {
            touch(d)
            return Prepared(id: id, title: (try? String(contentsOf: titleFile, encoding: .utf8)) ?? "YouTube video")
        }
        try? FileManager.default.removeItem(at: d)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        prune(keeping: 10)

        // 1. Resolve stream URLs (+ the headers YouTube expects) with yt-dlp.
        let h = quality.rawValue
        let format = "bv*[vcodec^=avc1][height<=\(h)][fps<=30]+ba[acodec^=mp4a]/bv*[vcodec^=avc1][height<=\(h)]+ba[acodec^=mp4a]/b[vcodec^=avc1][ext=mp4]"
        let probe = await Shell.run(["yt-dlp", "-j", "--no-playlist", "--no-warnings", "-f", format,
                                     "https://www.youtube.com/watch?v=\(id)"], timeout: 60)
        guard let line = probe.output.split(separator: "\n").last(where: { $0.hasPrefix("{") }),
              let info = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw StreamError(message: probe.output.contains("ERROR")
                ? (probe.output.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init) ?? "YouTube refused the video")
                : "Couldn't read this video. Is yt-dlp installed? (brew install yt-dlp)")
        }
        let title = info["title"] as? String ?? "YouTube video"
        try? title.write(to: titleFile, atomically: true, encoding: .utf8)
        let formats = (info["requested_formats"] as? [[String: Any]]) ?? [info]
        var inputs: [String] = []
        for f in formats {
            guard let url = f["url"] as? String else { continue }
            if let headers = f["http_headers"] as? [String: String] {
                inputs += ["-headers", headers.map { "\($0.key): \($0.value)\r\n" }.joined()]
            }
            inputs += ["-i", url]
        }
        guard !inputs.isEmpty else { throw StreamError(message: "No playable stream found") }

        // 2. Remux into 4-second fMP4 segments while downloading.
        var args = ["-hide_banner", "-loglevel", "error", "-y"] + inputs
        if formats.count > 1 { args += ["-map", "0:v:0", "-map", "1:a:0"] }
        args += ["-c", "copy", "-f", "hls", "-hls_time", "4", "-hls_playlist_type", "event",
                 "-hls_segment_type", "fmp4", "-hls_fmp4_init_filename", "init.mp4",
                 "-hls_segment_filename", d.appendingPathComponent("seg%d.m4s").path,
                 d.appendingPathComponent("index.m3u8").path]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        if !FileManager.default.isExecutableFile(atPath: p.executableURL!.path) {
            p.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        }
        p.arguments = args
        p.currentDirectoryURL = d
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle(forWritingAtPath: "/dev/null")
        let jobKey = "\(id)-\(h)"
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.lock()
            self.jobs[jobKey] = nil
            self.lock.unlock()
            if proc.terminationStatus == 0 {
                FileManager.default.createFile(atPath: d.appendingPathComponent("done").path, contents: nil)
            }
        }
        do { try p.run() } catch { throw StreamError(message: "ffmpeg is missing (brew install ffmpeg)") }
        register(jobKey, p)

        // 3. Ready once the first segment exists (≈4 s of video); the rest streams in.
        for _ in 0..<240 {
            if completeSegments(d) >= 1 || isComplete(d) { return Prepared(id: id, title: title) }
            if !p.isRunning && !isComplete(d) { throw StreamError(message: "YouTube stopped the download. Try again.") }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw StreamError(message: "The video is loading too slowly on this connection. Try 480p.")
    }

    /// Stops downloads other than the given video (a new video replaces the old one).
    func cancelOthers(except id: String) {
        lock.lock()
        let others = jobs.filter { !$0.key.hasPrefix(id + "-") }
        lock.unlock()
        others.values.forEach { $0.terminate() }
    }

    // MARK: - Serving (called from the HTTP server's queue)

    enum Segment {
        case data(Data)
        case notYet
        case end
        case missing
    }

    func initSegment(key: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(key).appendingPathComponent("init.mp4"))
    }

    /// Segment `n` once ffmpeg has finished it (it is listed in the playlist).
    func segment(key: String, n: Int) -> Segment {
        let d = root.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: d.path) else { return .missing }
        if n < completeSegments(d), let data = try? Data(contentsOf: d.appendingPathComponent("seg\(n).m4s")) {
            return .data(data)
        }
        return isComplete(d) || !isRunning(key: key) ? .end : .notYet
    }

    // MARK: - Helpers

    private func completeSegments(_ d: URL) -> Int {
        guard let text = try? String(contentsOf: d.appendingPathComponent("index.m3u8"), encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { $0.hasSuffix(".m4s") }.count
    }

    private func isComplete(_ d: URL) -> Bool {
        FileManager.default.fileExists(atPath: d.appendingPathComponent("done").path)
    }

    private func isRunning(_ id: String, _ q: Quality) -> Bool { isRunning(key: "\(id)-\(q.rawValue)") }

    private func isRunning(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return jobs[key]?.isRunning == true
    }

    private func touch(_ d: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: d.path)
    }

    /// Keeps the most recently played videos, removes older ones.
    private func prune(keeping limit: Int) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = dirs.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(limit) where !isRunning(key: old.lastPathComponent) {
            try? fm.removeItem(at: old)
        }
    }
}
