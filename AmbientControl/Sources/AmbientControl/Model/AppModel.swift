import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let port: UInt16 = 8787

    private(set) var state: TVState
    private(set) var library: [MediaItem] = []
    private(set) var streams: [MediaItem] = []
    var lanIP: String = LAN.ipv4() ?? "127.0.0.1"
    var serverError: String?
    var tvLastSeen: Date?
    var tvClientIP: String?
    var toast: String?

    let tv = TVController()
    let link = TVLink()
    let screen = ScreenShare()
    let feeds = LiveFeeds()
    /// Settings changed while Ambient was not open on the TV (applied when it opens).
    var tvPending = false
    /// When the Dynamic Island timer on the TV finishes (for the Mac's own countdown).
    private(set) var timerEndsAt: Date?
    private(set) var youtubeRecents: [YouTubeVideo] = []
    let paths: Paths
    @ObservationIgnored let store: SharedStore
    @ObservationIgnored private var server: HTTPServer?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var expireTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init() {
        let p = Paths()
        paths = p
        var loaded = Self.load(TVState.self, from: p.stateFile) ?? TVState()
        loaded.message = nil
        loaded.command = nil
        if loaded.media?.isScreen == true { loaded.media = nil }  // a share never survives a restart
        loaded.activity = nil
        if loaded.media?.isYouTube == true { loaded.media = nil }  // don't resume a video after a restart
        state = loaded
        streams = Self.load([MediaItem].self, from: p.streamsFile) ?? []
        youtubeRecents = Self.load([YouTubeVideo].self, from: p.youtubeFile) ?? []
        YouTubeStreamer.shared.configure(cacheDir: p.supportDir.appendingPathComponent("youtube-cache", isDirectory: true))
        store = SharedStore(mediaDir: p.mediaDir, tvAppDir: p.tvAppDir, port: Self.port)
        rescanLibrary()
        startServer()
        Task { await startLink() }
        feeds.start(self)
    }

    private func startLink() async {
        if link.host.isEmpty { await link.discover(subnetOf: lanIP) }
        if link.paired { await link.connect() }
    }

    var serverAddress: String { "\(lanIP):\(Self.port)" }
    var previewURL: URL { URL(string: "http://127.0.0.1:\(Self.port)/tv/index.html?preview=1&server=127.0.0.1:\(Self.port)")! }

    var tvConnected: Bool {
        guard let seen = tvLastSeen else { return false }
        return Date().timeIntervalSince(seen) < 10
    }

    // MARK: - Server

    func startServer() {
        let s = HTTPServer(store: store)
        store.setPollHandler { [weak self] host in
            Task { @MainActor in
                self?.tvLastSeen = Date()
                self?.tvClientIP = host
            }
        }
        do {
            try s.start { [weak self] err in
                Task { @MainActor in self?.serverError = err }
            }
            server = s
        } catch {
            serverError = "Could not start server on port \(Self.port): \(error.localizedDescription)"
        }
        publish()
    }

    private func publish() {
        store.publish(state: state, library: library + streams, lanIP: lanIP)
    }

    // MARK: - State changes

    /// Settings the TV should re-apply (widgets, wallpaper, quotes…): bumps `rev`.
    func updateSettings(_ change: (inout TVState) -> Void) {
        change(&state)
        state.showQuotes = state.shows(.quote)
        state.rev += 1
        commit()
        schedulePush()
    }

    /// Background data (weather, events, music…): served to polling TVs, no `rev` bump.
    func updateLive(_ change: (inout LiveData) -> Void) {
        var live = state.live
        change(&live)
        guard live != state.live else { return }
        updateRuntime { $0.live = live }
    }

    /// Runtime changes (what is playing, messages, commands): no `rev` bump.
    private func updateRuntime(_ change: (inout TVState) -> Void) {
        change(&state)
        commit()
    }

    /// Playback changes: saved, served to polling TVs, and pushed over Wi-Fi.
    private func updatePlayback(_ change: (inout TVState) -> Void) {
        updateRuntime(change)
        schedulePush()
    }

    private func commit() {
        state.updatedAt = Int(Date().timeIntervalSince1970)
        publish()
        Self.save(state, to: paths.stateFile)
    }

    private var eventID: Int { Int(Date().timeIntervalSince1970 * 1000) }

    func send(command action: String) {
        updateRuntime { $0.command = TVCommand(id: eventID, action: action) }
        deliverEvent(sent: nil)
    }

    func send(message text: String, seconds: Int = 8) {
        sendNotification(title: "", text: text, icon: .message, color: .blue, seconds: seconds)
    }

    // MARK: - Dynamic Island

    func sendNotification(title: String, text: String, icon: IslandIcon, color: IslandColor, seconds: Int = 8) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(title.isEmpty && text.isEmpty) else { return }
        updateRuntime {
            $0.message = TVMessage(id: eventID, text: text, seconds: seconds,
                                   title: title.isEmpty ? nil : title, icon: icon.rawValue, color: color.rawValue)
        }
        deliverEvent(sent: "Sent to TV", toast: [title, text].filter { !$0.isEmpty }.joined(separator: ": "))
    }

    /// Starts a countdown that lives in the TV's Dynamic Island and announces itself when done.
    func startTimer(title: String, seconds: Int) {
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Timer" : title
        updateRuntime { $0.activity = TVActivity(id: eventID, title: name, durationSec: seconds) }
        timerEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
        schedulePush()
        timerTask?.cancel()
        timerTask = Task {
            try? await Task.sleep(for: .seconds(seconds + 3))
            guard !Task.isCancelled else { return }
            updateRuntime { $0.activity = nil }
            timerEndsAt = nil
        }
        flash("Timer started on TV")
    }

    func cancelTimer() {
        timerTask?.cancel()
        updateRuntime { $0.activity = nil }
        timerEndsAt = nil
        schedulePush()
    }

    // MARK: - YouTube

    /// What the YouTube page shows while a video is being prepared.
    private(set) var youtubeStatus: String?
    var youtubeQuality: YouTubeStreamer.Quality = YouTubeStreamer.Quality(
        rawValue: UserDefaults.standard.integer(forKey: "ytQuality")) ?? .p720 {
        didSet { UserDefaults.standard.set(youtubeQuality.rawValue, forKey: "ytQuality") }
    }

    /// Starts fetching as soon as a link is pasted, so Play starts almost immediately.
    func prefetchYouTube(_ id: String) {
        let q = youtubeQuality
        Task.detached { _ = try? await YouTubeStreamer.shared.prepare(id: id, quality: q) }
    }

    /// Plays the video fullscreen inside Ambient on the TV, with sound through the TV speakers.
    /// Playback starts after the first ~8 seconds have downloaded; the rest streams in.
    @discardableResult
    func playYouTube(_ input: String) async -> Bool {
        guard let id = YouTube.videoID(from: input) else {
            flash("That doesn't look like a YouTube link")
            return false
        }
        youtubeStatus = "Getting the video from YouTube…"
        defer { youtubeStatus = nil }
        YouTubeStreamer.shared.cancelOthers(except: id)
        do {
            let prepared = try await YouTubeStreamer.shared.prepare(id: id, quality: youtubeQuality)
            youtubeStatus = "Starting on the TV…"
            updatePlayback {
                $0.media = MediaItem(name: prepared.title, url: "/yt/\(id)-\(youtubeQuality.rawValue)", type: "youtube")
                $0.playlist = []
                $0.playlistIndex = 0
            }
            if screen.isSharing { await screen.stop() }
            await openOnTV()
            flash("Playing on the TV")
            await remember(id)
            return true
        } catch {
            flash(error.localizedDescription)
            return false
        }
    }

    private func remember(_ id: String) async {
        var video = youtubeRecents.first { $0.id == id } ?? YouTubeVideo(id: id, title: "YouTube video", author: "", addedAt: Date())
        video.addedAt = Date()
        youtubeRecents.removeAll { $0.id == id }
        youtubeRecents.insert(video, at: 0)
        youtubeRecents = Array(youtubeRecents.prefix(24))
        Self.save(youtubeRecents, to: paths.youtubeFile)
        if video.title == "YouTube video", let info = await YouTube.info(for: id),
           let i = youtubeRecents.firstIndex(where: { $0.id == id }) {
            youtubeRecents[i].title = info.title
            youtubeRecents[i].author = info.author
            Self.save(youtubeRecents, to: paths.youtubeFile)
        }
    }

    func forgetYouTube(_ video: YouTubeVideo) {
        youtubeRecents.removeAll { $0.id == video.id }
        Self.save(youtubeRecents, to: paths.youtubeFile)
    }

    // MARK: - Wi-Fi push

    /// Messages and commands are pushed right away, and expire after 10 s so a TV that
    /// opens Ambient later does not replay them.
    /// When the TV is busy in another app, notifications fall back to a native webOS toast.
    private func deliverEvent(sent: String?, toast: String? = nil) {
        Task {
            let ok = await pushToTV(includeEvents: true)
            var shown = ok || tvConnected
            if !ok, link.paired, tvPending, let toast, !toast.isEmpty {
                shown = await link.toast(toast)
            }
            if let sent {
                flash(shown ? sent : "Open Ambient on the TV to see it")
            }
        }
        expireTask?.cancel()
        expireTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            updateRuntime {
                $0.message = nil
                $0.command = nil
            }
        }
    }

    /// Settings and playback changes are batched (sliders send many changes).
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await pushToTV(includeEvents: false)
        }
    }

    /// Sends the full state to the TV over Wi-Fi. Without `force` it never interrupts:
    /// if Ambient is not the app on screen, the change waits until it opens.
    @discardableResult
    func pushToTV(includeEvents: Bool, force: Bool = false) async -> Bool {
        guard link.paired else { return false }
        if !force {
            guard await link.foregroundApp() == TVController.appID else {
                tvPending = true
                return false
            }
        }
        var snapshot = state
        if !includeEvents {
            snapshot.message = nil
            snapshot.command = nil
        }
        guard let data = try? JSONEncoder().encode(snapshot),
              let ambient = try? JSONSerialization.jsonObject(with: data) else { return false }
        let ok = await link.launch(TVController.appID, params: ["server": serverAddress, "ambient": ambient])
        if ok { tvPending = false }
        return ok
    }

    /// Opens Ambient on the TV with the latest settings: over Wi-Fi when paired, otherwise via Developer Mode.
    func openOnTV() async {
        lanIP = LAN.ipv4() ?? lanIP
        publish()
        if link.paired, await pushToTV(includeEvents: false, force: true) {
            flash("Ambient is open on the TV")
        } else {
            await tv.launch(server: serverAddress)
        }
    }

    func pairTV() async {
        if link.host.isEmpty { await link.discover(subnetOf: lanIP) }
        if await link.connect(allowPrompt: true) {
            flash("Paired with the TV")
            await pushToTV(includeEvents: false)
        }
    }

    // MARK: - Playback

    func show(_ item: MediaItem) {
        if screen.isSharing { Task { await screen.stop() } }
        updatePlayback {
            $0.media = item
            $0.playlist = []
            $0.playlistIndex = 0
        }
        flash("Showing \(item.name)")
    }

    func playPlaylist(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        updatePlayback {
            $0.playlist = items
            $0.playlistIndex = 0
            $0.media = nil
        }
        flash("Playing \(items.count) items")
    }

    func addToPlaylist(_ item: MediaItem) {
        guard !state.playlist.contains(item) else { return }
        updatePlayback {
            $0.playlist.append(item)
            $0.media = nil
        }
    }

    func removeFromPlaylist(_ item: MediaItem) {
        updatePlayback { $0.playlist.removeAll { $0 == item } }
    }

    func movePlaylist(from: IndexSet, to: Int) {
        updatePlayback { $0.playlist.move(fromOffsets: from, toOffset: to) }
    }

    func stopMedia() {
        if screen.isSharing { Task { await screen.stop() } }
        updatePlayback {
            $0.media = nil
            $0.playlist = []
            $0.playlistIndex = 0
        }
        flash("Back to Ambient")
    }

    // MARK: - Screen share

    /// Starts capturing the selected display and opens it fullscreen on the TV.
    func startScreenShare() async {
        guard await screen.start() else { return }
        let name = screen.selected?.name ?? "Mac screen"
        updatePlayback {
            // a fresh URL each time so the TV reconnects to the new stream
            $0.media = MediaItem(name: name, url: "/screen?s=\(eventID)", type: "screen")
            $0.playlist = []
            $0.playlistIndex = 0
        }
        await openOnTV()
        flash("Sharing \(name)")
    }

    /// Streams the Mac's Weather app window to the TV, exactly as it looks on the Mac.
    func showWeatherApp() async {
        let id = "com.apple.weather"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        // the window takes a moment to appear after launch
        for _ in 0..<12 {
            if await screen.start(windowOf: id) { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard screen.isSharing else {
            flash(screen.error ?? "Could not capture the Weather app")
            return
        }
        updatePlayback {
            $0.media = MediaItem(name: "Weather", url: "/screen?s=\(eventID)", type: "screen")
            $0.playlist = []
            $0.playlistIndex = 0
        }
        await openOnTV()
        flash("Weather app is on the TV")
    }

    func stopScreenShare() async {
        await screen.stop()
        if state.media?.isScreen == true {
            updatePlayback { $0.media = nil }
        }
        flash("Screen sharing stopped")
    }

    var isPlaying: Bool { state.media != nil || !state.playlist.isEmpty }

    func isCurrent(_ item: MediaItem) -> Bool {
        state.media == item || state.playlist.contains(item)
    }

    // MARK: - Photo frame

    /// Plays photos fullscreen, one after another (all library photos when `items` is nil).
    func startPhotoFrame(_ items: [MediaItem]? = nil) {
        var photos = (items ?? library).filter { $0.type == "image" }
        guard !photos.isEmpty else {
            flash("Add some photos to the Library first")
            return
        }
        if state.photoFrame.shuffle { photos.shuffle() }
        if screen.isSharing { Task { await screen.stop() } }
        updatePlayback {
            $0.playlist = photos
            $0.playlistIndex = 0
            $0.media = photos.count == 1 ? photos[0] : nil
        }
        flash("Photo frame: \(photos.count) photo\(photos.count == 1 ? "" : "s")")
    }

    /// Imports every photo in a folder and starts the photo frame with them.
    func startPhotoFrame(folder: URL) {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let names = copyIn(files.filter { MediaKind.type(for: $0.lastPathComponent) == "image" })
        rescanLibrary()
        startPhotoFrame(library.filter { names.contains($0.name) })
    }

    // MARK: - Schedules

    func run(_ rule: ScheduleRule) {
        switch rule.action {
        case .openAmbient: Task { await openOnTV() }
        case .turnOffTV: Task { _ = await link.turnOff() }
        case .wallpaper: updateSettings { $0.wallpaper = rule.value; $0.customWallpaper = nil }
        case .brightness: updateSettings { $0.brightness = rule.value }
        case .warmOn: updateSettings { $0.tint = "warm" }
        case .warmOff: updateSettings { $0.tint = "none" }
        case .photoFrame: startPhotoFrame()
        case .stopMedia: stopMedia()
        }
    }

    // MARK: - Library

    func rescanLibrary() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: paths.mediaDir.path)) ?? []
        library = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { name in
            guard !name.hasPrefix("."), let type = MediaKind.type(for: name) else { return nil }
            let size = (try? fm.attributesOfItem(atPath: paths.mediaDir.appendingPathComponent(name).path)[.size] as? Int) ?? 0
            return MediaItem(name: name, url: "/media/" + name, type: type, size: size)
        }
        publish()
    }

    func fileURL(for item: MediaItem) -> URL? {
        item.isStream ? nil : paths.mediaDir.appendingPathComponent(item.name)
    }

    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        let count = copyIn(urls).count
        rescanLibrary()
        if count > 0 { flash("Imported \(count) item\(count == 1 ? "" : "s")") }
        return count
    }

    /// Copies supported files into the library; returns their new names.
    private func copyIn(_ urls: [URL]) -> [String] {
        var names: [String] = []
        for src in urls {
            guard MediaKind.type(for: src.lastPathComponent) != nil else { continue }
            let access = src.startAccessingSecurityScopedResource()
            defer { if access { src.stopAccessingSecurityScopedResource() } }
            let dest = uniqueDestination(for: src.lastPathComponent)
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil { names.append(dest.lastPathComponent) }
        }
        return names
    }

    private func uniqueDestination(for filename: String) -> URL {
        let safe = filename.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        var url = paths.mediaDir.appendingPathComponent(safe)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = paths.mediaDir.appendingPathComponent("\(base)_\(n).\(ext)")
            n += 1
        }
        return url
    }

    func delete(_ item: MediaItem) {
        if item.isStream {
            streams.removeAll { $0 == item }
            Self.save(streams, to: paths.streamsFile)
        } else if let url = fileURL(for: item) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        updateRuntime {
            if $0.media == item { $0.media = nil }
            $0.playlist.removeAll { $0 == item }
        }
        if state.customWallpaper?.name == item.name { clearCustomWallpaper() }
        rescanLibrary()
    }

    func addStream(_ raw: String, name: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: s), let scheme = url.scheme, ["http", "https"].contains(scheme) else { return false }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? (url.host ?? s) : name
        let type = MediaKind.type(for: url.lastPathComponent) ?? "video"
        let item = MediaItem(name: title, url: s, type: type)
        guard !streams.contains(item) else { return true }
        streams.append(item)
        Self.save(streams, to: paths.streamsFile)
        publish()
        return true
    }

    // MARK: - Wallpaper

    func setCustomWallpaper(_ item: MediaItem) {
        guard !item.isVideo, let src = fileURL(for: item) else { return }
        let stem = (item.name as NSString).deletingPathExtension
        let wall = paths.wallDir.appendingPathComponent(stem + ".jpg")
        let glass = paths.glassDir.appendingPathComponent(stem + ".jpg")
        do {
            try ImageTools.makeWallpaper(from: src, wallOut: wall, glassOut: glass)
        } catch {
            flash("Could not use this image as wallpaper")
            return
        }
        updateSettings {
            $0.customWallpaper = CustomWallpaper(name: item.name,
                                                 url: "/media/.wall/\(stem).jpg",
                                                 glass: "/media/.glass/\(stem).jpg")
        }
        flash("Wallpaper set")
    }

    /// Imports an image file from anywhere on the Mac and uses it as the wallpaper.
    func setCustomWallpaper(file: URL) {
        guard MediaKind.type(for: file.lastPathComponent) == "image", let name = copyIn([file]).first else {
            flash("Choose a photo (JPEG, PNG, HEIC…)")
            return
        }
        rescanLibrary()
        if let item = library.first(where: { $0.name == name }) { setCustomWallpaper(item) }
    }

    func clearCustomWallpaper() {
        updateSettings { $0.customWallpaper = nil }
    }

    func builtInWallpaperURL(_ file: String) -> URL? {
        paths.tvAppDir?.appendingPathComponent("images/\(file).jpg")
    }

    // MARK: - Helpers

    func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { toast = nil }
        }
    }


    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(value) { try? data.write(to: url, options: .atomic) }
    }
}

struct Paths {
    let supportDir: URL
    let mediaDir: URL
    let wallDir: URL
    let glassDir: URL
    let stateFile: URL
    let streamsFile: URL
    let youtubeFile: URL
    /// The webOS app (index.html, css, js, images) — bundled in Resources/tv.
    let tvAppDir: URL?
    /// Packaged TV app for one-click install.
    let ipk: URL?

    init() {
        let fm = FileManager.default
        supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmbientControl", isDirectory: true)
        mediaDir = supportDir.appendingPathComponent("media", isDirectory: true)
        wallDir = mediaDir.appendingPathComponent(".wall", isDirectory: true)
        glassDir = mediaDir.appendingPathComponent(".glass", isDirectory: true)
        stateFile = supportDir.appendingPathComponent("state.json")
        streamsFile = supportDir.appendingPathComponent("streams.json")
        youtubeFile = supportDir.appendingPathComponent("youtube.json")
        for dir in [supportDir, mediaDir, wallDir, glassDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let res = Bundle.main.resourceURL
        if let tv = res?.appendingPathComponent("tv"), fm.fileExists(atPath: tv.appendingPathComponent("index.html").path) {
            tvAppDir = tv
        } else if let env = ProcessInfo.processInfo.environment["AMBIENT_TV_DIR"] {
            tvAppDir = URL(fileURLWithPath: env)
        } else {
            tvAppDir = nil
        }
        ipk = (try? fm.contentsOfDirectory(at: res ?? supportDir, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "ipk" }
    }
}
