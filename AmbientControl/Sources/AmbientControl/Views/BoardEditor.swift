import SwiftUI

enum BoardItem: Hashable {
    case clock
    case widget(WidgetKind)
}

/// The TV screen in miniature: drag widgets and the big clock anywhere, click one to edit it.
struct BoardEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: BoardItem?
    @ViewState private var dragging: BoardItem?
    @ViewState private var dragOffset: CGSize = .zero

    /// Big clock font size in vw for small / medium / large (matches the TV's CSS)
    static let clockSizes = [9.0, 13.2, 17.0]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                wallpaper
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .onTapGesture { selection = nil }

                if dragging != nil, centered(size) {
                    Rectangle()
                        .fill(Color.yellow.opacity(0.8))
                        .frame(width: 1, height: size.height)
                        .offset(x: size.width / 2)
                        .allowsHitTesting(false)
                }

                if model.state.showClock {
                    clockBlock(size)
                }
                ForEach(model.state.board) { w in
                    widgetBlock(w, size)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    // MARK: - Pieces

    @ViewBuilder private var wallpaper: some View {
        let s = model.state
        let url: URL? = if let custom = s.customWallpaper {
            model.paths.wallDir.appendingPathComponent((custom.url as NSString).lastPathComponent)
        } else {
            model.builtInWallpaperURL(BuiltInWallpaper.all[max(s.wallpaper, 0) % BuiltInWallpaper.all.count].file)
        }
        if let url, let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
        }
    }

    private func clockBlock(_ size: CGSize) -> some View {
        let st = model.state.clockStyle
        let font = Self.clockSizes[min(max(st.size, 0), 2)] / 100 * size.width
        let selected = selection == .clock
        let offset = dragging == .clock ? dragOffset : .zero
        return VStack(spacing: 0) {
            if model.state.showDate {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: font * 0.15, weight: .semibold))
            }
            Text(Date.now, format: .dateTime.hour(.twoDigits(amPM: model.state.use24h ? .omitted : .abbreviated)).minute())
                .font(.system(size: font, weight: Font.Weight(css: st.weight)))
                .foregroundStyle(Color(hex: st.color))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .frame(width: size.width)
        .offset(x: (st.x - 0.5) * size.width + offset.width, y: st.y * size.height + offset.height)
        .gesture(drag(.clock, size: size))
        .onTapGesture { selection = .clock }
    }

    private func widgetBlock(_ w: PlacedWidget, _ size: CGSize) -> some View {
        let item = BoardItem.widget(w.kind)
        let selected = selection == item
        let offset = dragging == item ? dragOffset : .zero
        let width = w.width * size.width
        let height = w.height * size.height
        let radius = height * 2.9 / 13
        return ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(selected ? Color.accentColor : .white.opacity(0.35), lineWidth: selected ? 2.5 : 1)
            VStack(spacing: 4) {
                Image(systemName: w.kind.symbol)
                    .font(.system(size: height * 0.28, weight: .semibold))
                Text(w.kind.title)
                    .font(.system(size: max(9, height * 0.11), weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .padding(4)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) {
            if selected {
                Button {
                    remove(w.kind)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: -8, y: -8)
                .help("Remove widget")
            }
        }
        .scaleEffect(dragging == item ? 1.04 : 1)
        .shadow(color: .black.opacity(dragging == item ? 0.4 : 0.2), radius: dragging == item ? 12 : 4)
        .offset(x: w.x * size.width + offset.width, y: w.y * size.height + offset.height)
        .gesture(drag(item, size: size))
        .onTapGesture { selection = item }
        .animation(.spring(duration: 0.3), value: w)
    }

    // MARK: - Dragging

    private func drag(_ item: BoardItem, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                dragging = item
                selection = item
                dragOffset = v.translation
            }
            .onEnded { v in
                let dx = v.translation.width / size.width
                let dy = v.translation.height / size.height
                switch item {
                case .clock:
                    var c = model.state.clockStyle
                    c.x = snap(min(max(c.x + dx, 0.15), 0.85))
                    if abs(c.x - 0.5) < 0.015 { c.x = 0.5 }
                    c.y = snap(min(max(c.y + dy, 0), 0.75))
                    model.updateSettings { $0.clockStyle = c }
                case .widget(let kind):
                    guard var w = model.state.board.first(where: { $0.kind == kind }) else { break }
                    w.x = snap(w.x + dx)
                    w.y = snap(w.y + dy)
                    if abs(w.x + w.width / 2 - 0.5) < 0.015 { w.x = 0.5 - w.width / 2 }
                    place(Board.clamp(w))
                }
                dragging = nil
                dragOffset = .zero
            }
    }

    /// While dragging: is the item's center on the screen's center line?
    private func centered(_ size: CGSize) -> Bool {
        let dx = dragOffset.width / size.width
        switch dragging {
        case .clock:
            return abs(model.state.clockStyle.x + dx - 0.5) < 0.015
        case .widget(let kind):
            guard let w = model.state.board.first(where: { $0.kind == kind }) else { return false }
            return abs(w.x + dx + w.width / 2 - 0.5) < 0.015
        case nil:
            return false
        }
    }

    /// Half-percent grid
    private func snap(_ v: Double) -> Double { (v * 200).rounded() / 200 }

    private func place(_ w: PlacedWidget) {
        model.updateSettings { s in
            if let i = s.board.firstIndex(where: { $0.kind == w.kind }) { s.board[i] = w }
        }
    }

    private func remove(_ kind: WidgetKind) {
        model.updateSettings { $0.board.removeAll { $0.kind == kind } }
        selection = nil
    }
}

/// Edits the selected widget (or the big clock) under the layout editor.
struct BoardInspector: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: BoardItem?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                switch selection {
                case .widget(let kind):
                    if let w = model.state.board.first(where: { $0.kind == kind }) {
                        HStack {
                            Label(kind.title, systemImage: kind.symbol).font(.headline)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                model.updateSettings { $0.board.removeAll { $0.kind == kind } }
                                selection = nil
                            }
                        }
                        Picker("Size", selection: Binding(
                            get: { w.size },
                            set: { size in
                                var n = w
                                n.size = size
                                n = Board.clamp(n)
                                model.updateSettings { s in
                                    if let i = s.board.firstIndex(where: { $0.kind == kind }) { s.board[i] = n }
                                }
                            }
                        )) {
                            Text("Small").tag(0)
                            Text("Medium").tag(1)
                            Text("Large").tag(2)
                        }
                        .pickerStyle(.segmented)
                        WidgetOptions(kind: kind)
                    }
                case .clock:
                    HStack {
                        Label("Big Clock", systemImage: "clock").font(.headline)
                        Spacer()
                        Button("Center") { model.updateSettings { $0.clockStyle.x = 0.5 } }
                    }
                    Picker("Size", selection: model.setting(\.clockStyle.size)) {
                        Text("Small").tag(0)
                        Text("Medium").tag(1)
                        Text("Large").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Text("Weight, color and format are in the Clock card.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case nil:
                    Label("Arrange", systemImage: "hand.draw").font(.headline)
                    Text("Drag widgets and the clock anywhere. Click one to change its size or settings, or to remove it. Use + Add Widget to add more.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension Font.Weight {
    init(css: Int) {
        switch css {
        case ..<350: self = .light
        case ..<500: self = .regular
        case ..<650: self = .semibold
        default: self = .bold
        }
    }
}
