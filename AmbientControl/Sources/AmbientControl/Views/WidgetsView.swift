import SwiftUI
import UniformTypeIdentifiers

struct WidgetsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var selection: BoardItem?
    @ViewState private var livePreview = false

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PaneHeader(title: "Widgets", subtitle: "Customize the TV's lock screen")
                    WallpaperPicker()
                    settingsForm
                }
                .padding(.vertical, 32)
                .padding(.leading, 32)
            }
            .frame(width: 520)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Picker("", selection: $livePreview) {
                            Text("Arrange").tag(false)
                            Text("Live Preview").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                        Spacer()
                        Button("Row", systemImage: "rectangle.split.3x1") {
                            model.updateSettings { $0.board = Board.row($0.board.sorted { $0.x < $1.x }.map(\.kind)) }
                        }
                        .help("Line the widgets up in a row at the bottom")
                        addMenu
                    }
                    if livePreview {
                        TVPreview(cornerRadius: 18)
                    } else {
                        BoardEditor(selection: $selection)
                    }
                    Text("Changes reach the TV within 3 seconds.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !livePreview {
                        BoardInspector(selection: $selection)
                    }
                }
                .padding(.top, 104)
                .padding(.trailing, 32)
                .padding(.bottom, 32)
            }
        }
    }

    private var addMenu: some View {
        let missing = WidgetKind.allCases.filter { !model.state.shows($0) }
        return Menu {
            ForEach(missing) { kind in
                Button(kind.title, systemImage: kind.symbol) { add(kind) }
            }
        } label: {
            Label("Add Widget", systemImage: "plus")
        }
        .fixedSize()
        .disabled(missing.isEmpty)
    }

    /// New widgets land in the middle of the screen, selected, ready to drag.
    private func add(_ kind: WidgetKind) {
        var w = PlacedWidget(kind: kind, x: 0, y: 0.42)
        w.x = 0.5 - w.width / 2
        model.updateSettings { $0.board.append(Board.clamp(w)) }
        selection = .widget(kind)
        livePreview = false
    }

    private var settingsForm: some View {
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Clock", "clock")
                    Toggle("Show clock", isOn: setting(\.showClock))
                    Toggle("Show date", isOn: setting(\.showDate))
                    Picker("Format", selection: setting(\.use24h)) {
                        Text("12-hour").tag(false)
                        Text("24-hour").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Weight", selection: setting(\.clockStyle.weight)) {
                        Text("Light").tag(300)
                        Text("Regular").tag(400)
                        Text("Semibold").tag(600)
                        Text("Bold").tag(700)
                    }
                    .pickerStyle(.segmented)
                    ColorRow(selection: setting(\.clockStyle.color))
                    Toggle("Show clock over photos and videos", isOn: setting(\.clockOverMedia))
                }
            }

            LocationCard()

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Extras", "sparkles")
                    Toggle(isOn: setting(\.widgets.dots)) { Label("Wallpaper dots", systemImage: "circle.grid.3x3") }
                    Toggle(isOn: setting(\.weather.effects)) {
                        Label("Weather on screen (rain, snow, clouds)", systemImage: "cloud.rain")
                    }
                    if model.state.weather.effects && !model.state.location.isSet {
                        Text("Set your city in Location to see the weather.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Display", "sun.max")
                    Picker("Brightness", selection: setting(\.brightness)) {
                        Text("Low").tag(0)
                        Text("Medium").tag(1)
                        Text("High").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Warm tint (easier on the eyes at night)", isOn: Binding(
                        get: { model.state.tint == "warm" },
                        set: { on in model.updateSettings { $0.tint = on ? "warm" : "none" } }
                    ))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Change quote every \(model.state.intervalSec) seconds")
                        Slider(value: Binding(
                            get: { Double(model.state.intervalSec) },
                            set: { v in model.updateSettings { $0.intervalSec = Int(v) } }
                        ), in: 10...300, step: 5)
                        Text("Wallpapers rotate every 4 quotes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Night Mode", "moon.stars")
                    Toggle("Dim the screen at night", isOn: setting(\.night.enabled))
                    HStack {
                        Picker("From", selection: setting(\.night.start)) {
                            ForEach(0..<24, id: \.self) { Text(hour($0)).tag($0) }
                        }
                        Picker("Until", selection: setting(\.night.end)) {
                            ForEach(0..<24, id: \.self) { Text(hour($0)).tag($0) }
                        }
                    }
                    .disabled(!model.state.night.enabled)
                }
            }
        }
        .toggleStyle(.switch)
    }

    private func sectionTitle(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.headline)
    }

    private func hour(_ h: Int) -> String {
        String(format: "%02d:00", h)
    }

    private func setting<T>(_ kp: WritableKeyPath<TVState, T>) -> Binding<T> {
        model.setting(kp)
    }
}

extension AppModel {
    /// A binding that writes through `updateSettings` (bumps `rev`, pushes to the TV).
    func setting<T>(_ kp: WritableKeyPath<TVState, T>) -> Binding<T> {
        Binding(get: { self.state[keyPath: kp] }, set: { v in self.updateSettings { $0[keyPath: kp] = v } })
    }
}

/// Clock colour swatches.
private struct ColorRow: View {
    @Binding var selection: String
    static let colors = ["#ffffff", "#ffd60a", "#ff9f0a", "#ff6482", "#bf5af2", "#64d2ff", "#30d158", "#ffb3a7"]

    var body: some View {
        HStack(spacing: 10) {
            Text("Color")
            Spacer()
            ForEach(Self.colors, id: \.self) { hex in
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle().strokeBorder(selection == hex ? Color.accentColor : .white.opacity(0.25),
                                                  lineWidth: selection == hex ? 3 : 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xffffff
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// City used by weather, sunrise/sunset and prayer times.
private struct LocationCard: View {
    @Environment(AppModel.self) private var model
    @ViewState private var query = ""
    @ViewState private var results: [Location] = []
    @ViewState private var searching = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Location", systemImage: "location").font(.headline)
                Text(model.state.location.isSet ? model.state.location.name
                     : (model.state.location.auto ? "Finding this Mac's location…" : "Not set. Used for weather and prayer times."))
                    .foregroundStyle(model.state.location.isSet ? .primary : .secondary)
                HStack {
                    Toggle("Use this Mac's location", isOn: Binding(
                        get: { model.state.location.auto },
                        set: { on in
                            model.updateSettings { $0.location.auto = on }
                            model.feeds.refreshNow()
                        }
                    ))
                    .toggleStyle(.switch)
                    Spacer()
                    if model.state.location.auto {
                        Button("Update", systemImage: "location.fill") { model.feeds.refreshNow() }
                    }
                }
                if !model.state.location.auto {
                HStack {
                    TextField("Search for your city", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(search)
                    Button("Search", action: search)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                }
                ForEach(results, id: \.name) { loc in
                    Button {
                        model.updateSettings { s in
                            s.location = loc
                            s.location.auto = false
                            s.live.weather = nil
                            s.live.prayer = nil
                        }
                        model.feeds.refreshNow()
                        results = []
                        query = ""
                    } label: {
                        Label(loc.name, systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            results = await LiveFeeds.searchCity(q)
            searching = false
            if results.isEmpty { model.flash("No city found") }
        }
    }
}

/// Extra settings shown under a widget while it is switched on.
struct WidgetOptions: View {
    @Environment(AppModel.self) private var model
    let kind: WidgetKind
    @ViewState private var calendarAllowed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch kind {
            case .clock:
                Picker("Face", selection: model.setting(\.widgets.clockFace)) {
                    ForEach(ClockFace.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            case .weather:
                Picker("Units", selection: Binding(
                    get: { model.state.weather.fahrenheit },
                    set: { f in model.updateSettings { $0.weather.fahrenheit = f }; model.feeds.refreshNow() }
                )) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
                needsLocation
                Button("Show the Weather App on the TV", systemImage: "cloud.sun") {
                    Task { await model.showWeatherApp() }
                }
                caption("Streams the Mac's Weather app window fullscreen, exactly as it looks on the Mac. Stop it from Now Playing.")
            case .world:
                Picker("City", selection: Binding(
                    get: { model.state.worldClock.timeZone },
                    set: { tz in
                        let city = WorldCities.all.first { $0.tz == tz }?.name ?? tz
                        model.updateSettings { $0.worldClock = WorldClockConfig(city: city, timeZone: tz) }
                    }
                )) {
                    ForEach(WorldCities.all, id: \.tz) { Text($0.name).tag($0.tz) }
                }
            case .events:
                if model.feeds.calendarAccess || calendarAllowed {
                    caption("Shows the next events from the Calendar app (today and tomorrow).")
                } else {
                    Button("Allow Calendar Access") {
                        Task { calendarAllowed = await model.feeds.requestCalendarAccess() }
                    }
                }
            case .music:
                caption("Shows what Music or Spotify is playing. macOS asks permission the first time.")
            case .prayer:
                Picker("Method", selection: model.setting(\.prayer.method)) {
                    ForEach(LiveFeeds.prayerMethods, id: \.id) { Text($0.name).tag($0.id) }
                }
                .onChange(of: model.state.prayer.method) { model.feeds.refreshNow() }
                needsLocation
            case .countdown:
                CountdownEditor()
            case .notes:
                TextField("Title", text: model.setting(\.notes.title))
                    .textFieldStyle(.roundedBorder)
                TextField("One item per line", text: Binding(
                    get: { model.state.notes.items.joined(separator: "\n") },
                    set: { v in model.updateSettings { $0.notes.items = v.components(separatedBy: "\n") } }
                ), axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            case .calendar, .quote:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var needsLocation: some View {
        if !model.state.location.isSet {
            caption("Set your city in Location above.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

private struct CountdownEditor: View {
    @Environment(AppModel.self) private var model
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.state.countdowns) { c in
                HStack {
                    TextField("Title", text: field(c.id, \.title))
                        .textFieldStyle(.roundedBorder)
                    DatePicker("", selection: Binding(
                        get: { Self.fmt.date(from: c.date) ?? Date() },
                        set: { d in update(c.id) { $0.date = Self.fmt.string(from: d) } }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    Button {
                        model.updateSettings { $0.countdowns.removeAll { $0.id == c.id } }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                let date = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
                model.updateSettings { $0.countdowns.append(Countdown(title: "Holiday", date: Self.fmt.string(from: date))) }
            } label: {
                Label("Add countdown", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            Text("The TV shows the nearest upcoming one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func field(_ id: UUID, _ kp: WritableKeyPath<Countdown, String>) -> Binding<String> {
        Binding(get: { model.state.countdowns.first { $0.id == id }?[keyPath: kp] ?? "" },
                set: { v in update(id) { $0[keyPath: kp] = v } })
    }

    private func update(_ id: UUID, _ change: (inout Countdown) -> Void) {
        model.updateSettings { s in
            if let i = s.countdowns.firstIndex(where: { $0.id == id }) { change(&s.countdowns[i]) }
        }
    }
}

enum WorldCities {
    static let all: [(name: String, tz: String)] = [
        ("Honolulu", "Pacific/Honolulu"), ("Los Angeles", "America/Los_Angeles"), ("Denver", "America/Denver"),
        ("Chicago", "America/Chicago"), ("New York", "America/New_York"), ("Toronto", "America/Toronto"),
        ("Mexico City", "America/Mexico_City"), ("São Paulo", "America/Sao_Paulo"), ("London", "Europe/London"),
        ("Paris", "Europe/Paris"), ("Berlin", "Europe/Berlin"), ("Amsterdam", "Europe/Amsterdam"),
        ("Stockholm", "Europe/Stockholm"), ("Rome", "Europe/Rome"), ("Madrid", "Europe/Madrid"),
        ("Athens", "Europe/Athens"), ("Istanbul", "Europe/Istanbul"), ("Moscow", "Europe/Moscow"),
        ("Cairo", "Africa/Cairo"), ("Johannesburg", "Africa/Johannesburg"), ("Damascus", "Asia/Damascus"),
        ("Beirut", "Asia/Beirut"), ("Amman", "Asia/Amman"), ("Jerusalem", "Asia/Jerusalem"),
        ("Baghdad", "Asia/Baghdad"), ("Riyadh", "Asia/Riyadh"), ("Mecca", "Asia/Riyadh"),
        ("Kuwait", "Asia/Kuwait"), ("Doha", "Asia/Qatar"), ("Dubai", "Asia/Dubai"), ("Tehran", "Asia/Tehran"),
        ("Karachi", "Asia/Karachi"), ("Delhi", "Asia/Kolkata"), ("Bangkok", "Asia/Bangkok"),
        ("Singapore", "Asia/Singapore"), ("Hong Kong", "Asia/Hong_Kong"), ("Shanghai", "Asia/Shanghai"),
        ("Seoul", "Asia/Seoul"), ("Tokyo", "Asia/Tokyo"), ("Sydney", "Australia/Sydney"),
        ("Auckland", "Pacific/Auckland")
    ]
}

struct WallpaperPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Wallpaper", systemImage: "photo.on.rectangle").font(.headline)
                    Spacer()
                    Button("Choose Image…", systemImage: "photo.badge.plus", action: chooseImage)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        tile(title: "Auto", selected: model.state.wallpaper < 0 && model.state.customWallpaper == nil) {
                            ZStack {
                                LinearGradient(colors: [.blue, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "arrow.triangle.2.circlepath").font(.title2.weight(.semibold))
                            }
                        } action: {
                            model.updateSettings { $0.wallpaper = -1; $0.customWallpaper = nil }
                        }

                        ForEach(Array(BuiltInWallpaper.all.enumerated()), id: \.offset) { i, wp in
                            tile(title: wp.name, selected: model.state.wallpaper == i && model.state.customWallpaper == nil) {
                                if let url = model.builtInWallpaperURL(wp.file), let img = NSImage(contentsOf: url) {
                                    Image(nsImage: img).resizable().scaledToFill()
                                } else {
                                    Color.gray
                                }
                            } action: {
                                model.updateSettings { $0.wallpaper = i; $0.customWallpaper = nil }
                            }
                        }

                        if let custom = model.state.customWallpaper {
                            tile(title: "Yours", selected: true) {
                                let url = model.paths.wallDir.appendingPathComponent((custom.url as NSString).lastPathComponent)
                                if let img = NSImage(contentsOf: url) {
                                    Image(nsImage: img).resizable().scaledToFill()
                                } else {
                                    Color.gray
                                }
                            } action: {}
                        }
                    }
                    .padding(.vertical, 4)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.setCustomWallpaper(file: url)
                    return true
                }
                Text(model.state.customWallpaper == nil
                     ? "Choose any photo on your Mac, or drop one here, to use it as the background."
                     : "Using your photo. Pick any wallpaper above to switch back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo for the TV background"
        if panel.runModal() == .OK, let url = panel.url {
            model.setCustomWallpaper(file: url)
        }
    }

    private func tile<Thumb: View>(title: String, selected: Bool, @ViewBuilder thumb: () -> Thumb, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumb()
                    .frame(width: 112, height: 63)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Color.accentColor : .white.opacity(0.15), lineWidth: selected ? 3 : 1)
                    }
                Text(title)
                    .font(.caption.weight(selected ? .bold : .regular))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
