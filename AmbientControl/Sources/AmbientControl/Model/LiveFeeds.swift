import AppKit
import EventKit
import Foundation

/// Refreshes `TVState.live` in the background: weather, prayer times, calendar events,
/// what Music/Spotify is playing and the world clock offset. Also runs the schedules.
/// Each feed only runs while its widget is switched on.
@MainActor
final class LiveFeeds {
    private weak var model: AppModel?
    private var loop: Task<Void, Never>?
    private let locator = MacLocation()
    private var nextLocate = Date.distantPast
    private var nextWeather = Date.distantPast
    private var nextPrayer = Date.distantPast
    private var nextEvents = Date.distantPast
    private var lastScheduleMinute = ""
    private var musicTrack = ""
    private var musicArt: String?
    private let eventStore = EKEventStore()

    var calendarAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func start(_ model: AppModel) {
        self.model = model
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.nextEvents = .distantPast }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Settings that affect a feed changed (location, units…): fetch again now.
    func refreshNow() {
        nextLocate = .distantPast
        nextWeather = .distantPast
        nextPrayer = .distantPast
        nextEvents = .distantPast
    }

    private func tick() async {
        guard let model else { return }
        runSchedules(model.state)

        if model.state.location.auto, Date() >= nextLocate {
            nextLocate = Date().addingTimeInterval(3 * 60 * 60)
            if let here = await locator.locate() {
                let old = model.state.location
                let moved = abs(here.latitude - old.latitude) > 0.05 || abs(here.longitude - old.longitude) > 0.05
                if moved || here.name != old.name {
                    model.updateSettings { $0.location = here }
                    nextWeather = .distantPast
                    nextPrayer = .distantPast
                }
            } else {
                nextLocate = Date().addingTimeInterval(120)
            }
        }
        let s = model.state

        if s.shows(.world) {
            let offset = TimeZone(identifier: s.worldClock.timeZone)?.secondsFromGMT()
            if offset != s.live.worldOffsetSec { model.updateLive { $0.worldOffsetSec = offset } }
        }
        if s.location.isSet, s.shows(.weather) || s.weather.effects, Date() >= nextWeather {
            nextWeather = Date().addingTimeInterval(15 * 60)
            if let w = await Self.fetchWeather(s.location, fahrenheit: s.weather.fahrenheit) {
                model.updateLive { $0.weather = w }
            } else {
                nextWeather = Date().addingTimeInterval(60)
            }
        }
        if s.location.isSet, s.shows(.prayer), Date() >= nextPrayer {
            nextPrayer = Date().addingTimeInterval(60 * 60)
            if let p = await Self.fetchPrayer(s.location, method: s.prayer.method) {
                model.updateLive { $0.prayer = p }
            } else {
                nextPrayer = Date().addingTimeInterval(60)
            }
        }
        if s.shows(.events), calendarAccess, Date() >= nextEvents {
            nextEvents = Date().addingTimeInterval(5 * 60)
            let list = upcomingEvents()
            if list != s.live.events { model.updateLive { $0.events = list } }
        }
        if s.shows(.music) {
            await refreshMusic(model)
        }
    }

    // MARK: - Location

    /// City search for the Location field (Open-Meteo geocoding, no key needed).
    static func searchCity(_ query: String) async -> [Location] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"), .init(name: "language", value: "en")]
        struct R: Decodable {
            struct P: Decodable {
                let name: String; let latitude: Double; let longitude: Double
                let country: String?; let admin1: String?; let timezone: String?
            }
            let results: [P]?
        }
        guard let url = c.url, let r: R = await get(url) else { return [] }
        return (r.results ?? []).map {
            let place = [$0.name, $0.admin1, $0.country].compactMap { $0 }.filter { !$0.isEmpty }
            var unique: [String] = []
            for p in place where !unique.contains(p) { unique.append(p) }
            return Location(name: unique.joined(separator: ", "), latitude: $0.latitude,
                            longitude: $0.longitude, timeZone: $0.timezone ?? "")
        }
    }

    // MARK: - Weather (Open-Meteo)

    private static func fetchWeather(_ loc: Location, fahrenheit: Bool) async -> LiveWeather? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(loc.latitude)),
            .init(name: "longitude", value: String(loc.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "5"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius")
        ]
        struct R: Decodable {
            struct Cur: Decodable { let temperature_2m: Double; let weather_code: Int }
            struct Day: Decodable {
                let time: [Int]; let weather_code: [Int]
                let temperature_2m_max: [Double]; let temperature_2m_min: [Double]
                let sunrise: [Int]; let sunset: [Int]
            }
            let current: Cur; let daily: Day; let timezone: String
        }
        guard let url = c.url, let r: R = await get(url), !r.daily.time.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.timeZone = TimeZone(identifier: r.timezone)
        let d = r.daily
        let days = (1..<d.time.count).map { i in
            LiveDay(d: f.string(from: Date(timeIntervalSince1970: TimeInterval(d.time[i]))),
                    code: d.weather_code[i],
                    hi: Int(d.temperature_2m_max[i].rounded()), lo: Int(d.temperature_2m_min[i].rounded()))
        }
        let city = loc.name.components(separatedBy: ",").first ?? loc.name
        return LiveWeather(city: city, temp: Int(r.current.temperature_2m.rounded()), code: r.current.weather_code,
                           hi: Int(d.temperature_2m_max[0].rounded()), lo: Int(d.temperature_2m_min[0].rounded()),
                           sunrise: d.sunrise[0], sunset: d.sunset[0], days: Array(days.prefix(4)))
    }

    // MARK: - Prayer times (Aladhan)

    private static func fetchPrayer(_ loc: Location, method: Int) async -> [LivePrayer]? {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        f.timeZone = TimeZone(identifier: loc.timeZone) ?? .current
        var c = URLComponents(string: "https://api.aladhan.com/v1/timings/\(f.string(from: Date()))")!
        c.queryItems = [.init(name: "latitude", value: String(loc.latitude)),
                        .init(name: "longitude", value: String(loc.longitude)),
                        .init(name: "method", value: String(method))]
        struct R: Decodable { struct D: Decodable { let timings: [String: String] }; let data: D }
        guard let url = c.url, let r: R = await get(url) else { return nil }
        let names = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let list = names.compactMap { n in r.data.timings[n].map { LivePrayer(name: n, time: String($0.prefix(5))) } }
        return list.count == names.count ? list : nil
    }

    static let prayerMethods: [(id: Int, name: String)] = [
        (3, "Muslim World League"), (4, "Umm al-Qura, Makkah"), (5, "Egyptian Authority"),
        (2, "ISNA (North America)"), (1, "Karachi"), (8, "Gulf Region"), (16, "Dubai"),
        (9, "Kuwait"), (10, "Qatar"), (13, "Turkey (Diyanet)"), (12, "France (UOIF)"),
        (11, "Singapore"), (15, "Moonsighting Committee")
    ]

    // MARK: - Calendar (EventKit)

    func requestCalendarAccess() async -> Bool {
        let ok = (try? await eventStore.requestFullAccessToEvents()) ?? false
        nextEvents = .distantPast
        return ok
    }

    private func upcomingEvents() -> [LiveEvent] {
        let now = Date()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        let pred = eventStore.predicateForEvents(withStart: cal.startOfDay(for: now), end: end, calendars: nil)
        return eventStore.events(matching: pred)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .prefix(4)
            .map { e in
                LiveEvent(title: e.title ?? "Event",
                          start: Int(e.startDate.timeIntervalSince1970), end: Int(e.endDate.timeIntervalSince1970),
                          allDay: e.isAllDay, color: Self.hex(e.calendar?.color))
            }
    }

    private static func hex(_ color: NSColor?) -> String {
        guard let c = color?.usingColorSpace(.sRGB) else { return "#ff6b61" }
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    // MARK: - Now Playing (Music / Spotify via AppleScript)

    private func refreshMusic(_ model: AppModel) async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var found: (info: [String], app: String)?
        for app in ["com.spotify.client", "com.apple.Music"] where running.contains(app) {
            let ms = app == "com.spotify.client" ? " / 1000" : ""
            let extra = app == "com.spotify.client" ? " & linefeed & (artwork url of t)" : ""
            let script = """
            tell application id "\(app)"
              if player state is stopped then return ""
              set t to current track
              return (name of t) & linefeed & (artist of t) & linefeed & ((player state is playing) as text) & linefeed & ((player position as integer) as text) & linefeed & (((duration of t)\(ms)) as integer as text)\(extra)
            end tell
            """
            let r = await Shell.run(["osascript", "-e", script], timeout: 8)
            let lines = r.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard r.ok, lines.count >= 5 else { continue }
            if found == nil || lines[2] == "true" { found = (lines, app) }
            if lines[2] == "true" { break }
        }
        guard let (info, app) = found else {
            if model.state.live.music != nil { model.updateLive { $0.music = nil } }
            return
        }
        let key = info[0] + "\u{1}" + info[1]
        if key != musicTrack {
            musicTrack = key
            musicArt = await artwork(app: app, url: info.count > 5 ? info[5] : nil, mediaDir: model.paths.mediaDir)
        }
        let now = Int(Date().timeIntervalSince1970)
        let next = LiveMusic(title: info[0], artist: info[1], art: musicArt, playing: info[2] == "true",
                             position: Double(info[3]) ?? 0, duration: Double(info[4]) ?? 0, at: now)
        if let old = model.state.live.music, old.title == next.title, old.artist == next.artist,
           old.playing == next.playing, old.art == next.art {
            let expected = old.position + (old.playing ? Double(now - old.at) : 0)
            if abs(expected - next.position) < 4 { return }
        }
        model.updateLive { $0.music = next }
    }

    /// Saves the album art as a small JPEG under media/.np and returns its URL path.
    private func artwork(app: String, url: String?, mediaDir: URL) async -> String? {
        let dir = mediaDir.appendingPathComponent(".np", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var data: Data?
        if let url, let u = URL(string: url), u.scheme == "https" {
            data = try? await URLSession.shared.data(from: u).0
        } else if app == "com.apple.Music" {
            let raw = dir.appendingPathComponent("raw.bin")
            let script = """
            tell application id "com.apple.Music" to set d to raw data of artwork 1 of current track
            set f to open for access (POSIX file "\(raw.path)") with write permission
            set eof f to 0
            write d to f
            close access f
            """
            _ = await Shell.run(["osascript", "-e", script], timeout: 8)
            data = try? Data(contentsOf: raw)
            try? FileManager.default.removeItem(at: raw)
        }
        guard let data, let image = NSImage(data: data) else { return nil }
        let size = NSSize(width: 300, height: 300)
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let name = "art-\(UUID().uuidString.prefix(8)).jpg"
        guard (try? jpg.write(to: dir.appendingPathComponent(name))) != nil else { return nil }
        return "/media/.np/\(name)"
    }

    // MARK: - Schedules

    private func runSchedules(_ s: TVState) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let minute = f.string(from: Date())
        guard minute != lastScheduleMinute else { return }
        lastScheduleMinute = minute
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        for rule in s.schedules where rule.enabled && rule.hour == c.hour && rule.minute == c.minute {
            model?.run(rule)
        }
    }

    // MARK: - Helpers

    private static func get<T: Decodable>(_ url: URL) async -> T? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
