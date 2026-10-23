import Foundation

/// The JSON document the TV app polls from `/api/state` every 3 seconds.
/// Settings changes bump `rev`; the TV only re-applies settings when `rev` changes.
/// `message` and `command` are one-shot events identified by `id`.
struct TVState: Codable, Equatable {
    var rev = 1
    var showClock = true
    var showDate = true
    var showQuotes = true
    var intervalSec = 30
    var media: MediaItem? = nil
    var playlist: [MediaItem] = []
    var playlistIndex = 0
    var widgets = WidgetSet()
    /// -1 = rotate automatically, 0...5 = fixed built-in wallpaper
    var wallpaper = -1
    var customWallpaper: CustomWallpaper? = nil
    /// 0 = low, 1 = medium, 2 = high
    var brightness = 2
    var use24h = true
    var clockOverMedia = true
    var night = NightMode()
    var quotes: [Quote] = []
    var clockStyle = ClockStyle()
    /// Where each widget sits on the TV screen (only widgets in here are shown)
    var board: [PlacedWidget] = Board.row(WidgetKind.defaultOn)
    var location = Location()
    var weather = WeatherConfig()
    var worldClock = WorldClockConfig()
    var prayer = PrayerConfig()
    var countdowns: [Countdown] = []
    var notes = NotesConfig()
    var photoFrame = PhotoFrame()
    /// "none" or "warm" (a soft amber filter for evenings)
    var tint = "none"
    /// Run by the Mac at set times (the TV ignores them)
    var schedules: [ScheduleRule] = []
    /// Data the Mac refreshes in the background (weather, events, music…). No `rev` bump.
    var live = LiveData()
    var message: TVMessage? = nil
    var command: TVCommand? = nil
    /// Live activity shown in the compact Dynamic Island (currently: a countdown timer)
    var activity: TVActivity? = nil
    var updatedAt = 0
}

/// Every key is optional, so state saved by older versions still loads.
extension TVState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TVState()
        rev = c.value(.rev, d.rev)
        showClock = c.value(.showClock, d.showClock)
        showDate = c.value(.showDate, d.showDate)
        showQuotes = c.value(.showQuotes, d.showQuotes)
        intervalSec = c.value(.intervalSec, d.intervalSec)
        media = c.value(.media, d.media)
        playlist = c.value(.playlist, d.playlist)
        playlistIndex = c.value(.playlistIndex, d.playlistIndex)
        widgets = c.value(.widgets, d.widgets)
        wallpaper = c.value(.wallpaper, d.wallpaper)
        customWallpaper = c.value(.customWallpaper, d.customWallpaper)
        brightness = c.value(.brightness, d.brightness)
        use24h = c.value(.use24h, d.use24h)
        clockOverMedia = c.value(.clockOverMedia, d.clockOverMedia)
        night = c.value(.night, d.night)
        quotes = c.value(.quotes, d.quotes)
        clockStyle = c.value(.clockStyle, d.clockStyle)
        // before the layout editor: the old on/off switches in a centered row
        board = c.value(.board, Board.row(WidgetKind.defaultOn.filter {
            switch $0 {
            case .calendar: widgets.calendar
            case .quote: widgets.quote
            default: widgets.analog
            }
        }))
        location = c.value(.location, d.location)
        weather = c.value(.weather, d.weather)
        worldClock = c.value(.worldClock, d.worldClock)
        prayer = c.value(.prayer, d.prayer)
        countdowns = c.value(.countdowns, d.countdowns)
        notes = c.value(.notes, d.notes)
        photoFrame = c.value(.photoFrame, d.photoFrame)
        tint = c.value(.tint, d.tint)
        schedules = c.value(.schedules, d.schedules)
        live = c.value(.live, d.live)
        message = c.value(.message, d.message)
        command = c.value(.command, d.command)
        activity = c.value(.activity, d.activity)
        updatedAt = c.value(.updatedAt, d.updatedAt)
    }

    func shows(_ kind: WidgetKind) -> Bool {
        board.contains { $0.kind == kind }
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct WidgetSet: Codable, Equatable {
    /// `calendar`, `quote` and `analog` are the switches from before the layout editor (`board`)
    var calendar = true
    var quote = true
    var analog = true
    var dots = true
    var clockFace = ClockFace.analog

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calendar = c.value(.calendar, true)
        quote = c.value(.quote, true)
        analog = c.value(.analog, true)
        dots = c.value(.dots, true)
        clockFace = c.value(.clockFace, .analog)
    }
}

/// A widget on the TV screen. `x`/`y` are its top-left corner as a fraction of the screen.
struct PlacedWidget: Codable, Equatable, Identifiable {
    var kind: WidgetKind
    var x: Double
    var y: Double
    /// 0 = small, 1 = medium, 2 = large
    var size = 1
    var id: WidgetKind { kind }

    static let scales = [0.75, 1.0, 1.35]
    var scale: Double { Self.scales[min(max(size, 0), 2)] }
    /// Size as a fraction of the screen width / height (16:9)
    var width: Double { kind.baseWidth / 100 * scale }
    var height: Double { WidgetKind.baseHeight / 56.25 * scale }
}

enum Board {
    /// Widgets side by side, centered near the bottom (the original layout).
    static func row(_ kinds: [WidgetKind]) -> [PlacedWidget] {
        let gap = 1.5
        let total = kinds.reduce(0) { $0 + $1.baseWidth } + gap * Double(max(kinds.count - 1, 0))
        var x = (100 - total) / 2
        let y = (56.25 - 5.4 - WidgetKind.baseHeight) / 56.25
        return kinds.map { k in
            defer { x += k.baseWidth + gap }
            return PlacedWidget(kind: k, x: x / 100, y: y)
        }
    }

    /// Keeps a widget fully on screen.
    static func clamp(_ w: PlacedWidget) -> PlacedWidget {
        var w = w
        w.x = min(max(w.x, 0), max(1 - w.width, 0))
        w.y = min(max(w.y, 0), max(1 - w.height, 0))
        return w
    }
}

enum ClockFace: String, Codable, CaseIterable, Identifiable {
    case analog, digital, stacked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .analog: "Analog"
        case .digital: "Digital"
        case .stacked: "Stacked"
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case calendar, quote, clock, weather, world, events, music, prayer, countdown, notes
    static let defaultOn: [WidgetKind] = [.calendar, .quote, .clock]
    var id: String { rawValue }

    /// Width in % of the screen width at medium size (matches the TV's CSS)
    var baseWidth: Double {
        switch self {
        case .calendar, .clock, .world, .countdown: 13
        case .quote: 44
        case .weather, .events, .music, .prayer: 27
        case .notes: 20
        }
    }
    /// Height in vw at medium size
    static let baseHeight = 13.0
    var title: String {
        switch self {
        case .calendar: "Date"
        case .quote: "Quote of the moment"
        case .clock: "Clock"
        case .weather: "Weather"
        case .world: "World clock"
        case .events: "Calendar events"
        case .music: "Now Playing"
        case .prayer: "Prayer times"
        case .countdown: "Countdown"
        case .notes: "Notes"
        }
    }
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .quote: "quote.opening"
        case .clock: "clock.fill"
        case .weather: "cloud.sun.fill"
        case .world: "globe"
        case .events: "list.bullet.rectangle"
        case .music: "music.note"
        case .prayer: "moon.stars.fill"
        case .countdown: "hourglass"
        case .notes: "checklist"
        }
    }
}

/// The big lock-screen clock.
struct ClockStyle: Codable, Equatable {
    /// CSS font weight: 300, 400, 600, 700
    var weight = 600
    /// 0 = small, 1 = medium, 2 = large
    var size = 1
    /// "#rrggbb"
    var color = "#ffffff"
    /// Center of the clock (x) and its top edge (y), as fractions of the screen
    var x = 0.5
    var y = 0.11

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClockStyle()
        weight = c.value(.weight, d.weight)
        size = c.value(.size, d.size)
        color = c.value(.color, d.color)
        x = c.value(.x, d.x)
        y = c.value(.y, d.y)
    }
}

/// Used by weather and prayer times.
struct Location: Codable, Equatable {
    var name = ""
    var latitude = 0.0
    var longitude = 0.0
    var timeZone = ""
    /// Follow this Mac's location (Location Services, or the internet connection as a fallback)
    var auto = true
    var isSet: Bool { !name.isEmpty }

    init(name: String = "", latitude: Double = 0, longitude: Double = 0, timeZone: String = "", auto: Bool = true) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.auto = auto
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
        latitude = c.value(.latitude, 0)
        longitude = c.value(.longitude, 0)
        timeZone = c.value(.timeZone, "")
        auto = c.value(.auto, true)
    }
}

struct WeatherConfig: Codable, Equatable {
    var fahrenheit = false
    /// Rain, snow and drifting clouds over the wallpaper, following the weather
    var effects = true
}

struct WorldClockConfig: Codable, Equatable {
    var city = "London"
    var timeZone = "Europe/London"
}

struct PrayerConfig: Codable, Equatable {
    /// Aladhan calculation method id
    var method = 3
}

struct Countdown: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// "yyyy-MM-dd"
    var date: String
}

struct NotesConfig: Codable, Equatable {
    var title = "Notes"
    var items: [String] = []
}

struct PhotoFrame: Codable, Equatable {
    /// Seconds per photo in a playlist (0 = change with each quote)
    var seconds = 20
    var shuffle = true
    /// Small clock in the bottom-left corner over photos instead of the big one
    var cornerClock = true
}

struct ScheduleRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var hour = 7
    var minute = 0
    var action = ScheduleAction.openAmbient
    /// Wallpaper index or brightness level, depending on `action`
    var value = 0
}

enum ScheduleAction: String, Codable, CaseIterable, Identifiable {
    case openAmbient, turnOffTV, wallpaper, brightness, warmOn, warmOff, photoFrame, stopMedia
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAmbient: "Open Ambient on the TV"
        case .turnOffTV: "Turn the TV off"
        case .wallpaper: "Change wallpaper"
        case .brightness: "Set brightness"
        case .warmOn: "Warm tint on"
        case .warmOff: "Warm tint off"
        case .photoFrame: "Start photo frame"
        case .stopMedia: "Back to Ambient (stop photos)"
        }
    }
}

/// Background data refreshed by `LiveFeeds`.
struct LiveData: Codable, Equatable {
    var weather: LiveWeather? = nil
    /// Seconds from UTC for the world clock city (refreshed so DST is followed)
    var worldOffsetSec: Int? = nil
    var events: [LiveEvent]? = nil
    var music: LiveMusic? = nil
    var prayer: [LivePrayer]? = nil
}

struct LiveWeather: Codable, Equatable {
    var city: String
    var temp: Int
    /// WMO weather code
    var code: Int
    var hi: Int
    var lo: Int
    /// Unix seconds, today
    var sunrise: Int
    var sunset: Int
    var days: [LiveDay]
}

struct LiveDay: Codable, Equatable {
    var d: String
    var code: Int
    var hi: Int
    var lo: Int
}

struct LiveEvent: Codable, Equatable {
    var title: String
    /// Unix seconds
    var start: Int
    var end: Int
    var allDay: Bool
    var color: String
}

struct LiveMusic: Codable, Equatable {
    var title: String
    var artist: String
    var art: String?
    var playing: Bool
    var position: Double
    var duration: Double
    /// Unix seconds when `position` was read
    var at: Int
}

struct LivePrayer: Codable, Equatable {
    var name: String
    /// "HH:mm" in the location's time
    var time: String
}

struct NightMode: Codable, Equatable {
    var enabled = true
    var start = 23
    var end = 6
}

struct CustomWallpaper: Codable, Equatable {
    var name: String
    var url: String
    var glass: String
}

/// A Dynamic Island notification.
struct TVMessage: Codable, Equatable {
    var id: Int
    var text: String
    var seconds: Int
    var title: String? = nil
    /// One of `IslandIcon` raw values
    var icon: String? = nil
    /// "#rrggbb"
    var color: String? = nil
}

struct TVActivity: Codable, Equatable {
    var id: Int
    var kind = "timer"
    var title: String
    var durationSec: Int
}

struct TVCommand: Codable, Equatable {
    var id: Int
    var action: String
}

struct Quote: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var t: String
    var a: String

    enum CodingKeys: String, CodingKey { case t, a }

    init(t: String, a: String) {
        self.t = t
        self.a = a
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(String.self, forKey: .t)
        a = try c.decodeIfPresent(String.self, forKey: .a) ?? ""
    }
}

struct MediaItem: Codable, Equatable, Hashable, Identifiable {
    var name: String
    /// `/media/<name>` for library files, or an absolute http(s) URL for streams
    var url: String
    /// "image", "video", "screen" (live Mac display) or "youtube" (streamed with sound)
    var type: String
    var size: Int = 0

    var id: String { url }
    var isVideo: Bool { type == "video" }
    /// Live stream of a Mac display
    var isScreen: Bool { type == "screen" }
    var isYouTube: Bool { type == "youtube" }
    var isStream: Bool { url.hasPrefix("http://") || url.hasPrefix("https://") }
}

enum MediaKind {
    static let image: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic"]
    static let video: Set<String> = ["mp4", "m4v", "webm", "mov"]

    static func type(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        if image.contains(ext) { return "image" }
        if video.contains(ext) { return "video" }
        return nil
    }
}

/// Built-in wallpapers shipped inside the TV app (images/bgN.jpg), in TV rotation order.
enum BuiltInWallpaper {
    static let all: [(name: String, file: String)] = [
        ("Blue", "bg1"), ("Sunset", "bg2"), ("Mint", "bg3"),
        ("Bloom", "bg5"), ("Ocean", "bg6"), ("Graphite", "bg4"),
        ("macOS 27 Light", "bg7"), ("macOS 27 Dark", "bg8"), ("Golden Gate", "bg9")
    ]
}
