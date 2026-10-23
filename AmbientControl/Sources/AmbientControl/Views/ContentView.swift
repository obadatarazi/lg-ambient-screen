import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case nowPlaying = "Now Playing"
    case library = "Library"
    case screen = "Screen Share"
    case youtube = "YouTube"
    case island = "Dynamic Island"
    case widgets = "Widgets"
    case photoFrame = "Photo Frame"
    case schedules = "Schedules"
    case quotes = "Quotes"
    case tv = "TV"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .nowPlaying: "play.tv"
        case .library: "photo.on.rectangle.angled"
        case .screen: "rectangle.on.rectangle"
        case .youtube: "play.rectangle"
        case .island: "capsule.inset.filled"
        case .widgets: "square.grid.2x2"
        case .photoFrame: "photo.artframe"
        case .schedules: "clock.badge.checkmark"
        case .quotes: "quote.bubble"
        case .tv: "tv.and.mediabox"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var pane: Pane? = .nowPlaying

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                ConnectionPill()
                    .padding(12)
            }
        } detail: {
            Group {
                switch pane ?? .nowPlaying {
                case .nowPlaying: NowPlayingView()
                case .library: LibraryView()
                case .screen: ScreenShareView()
                case .youtube: YouTubeView()
                case .island: IslandView()
                case .widgets: WidgetsView()
                case .photoFrame: PhotoFrameView()
                case .schedules: SchedulesView()
                case .quotes: QuotesView()
                case .tv: TVView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BackdropView())
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: model.toast)
        .task {
            await model.tv.refresh()
        }
    }
}

/// Soft colour wash behind the detail pane so the glass has something to refract.
struct BackdropView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.blue.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color.purple.opacity(0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

struct ConnectionPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let connected = model.link.ready || model.tvConnected
            HStack(spacing: 8) {
                Circle()
                    .fill(connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connected ? "TV connected" : (model.link.paired ? "TV offline" : "TV not paired"))
                        .font(.caption.weight(.semibold))
                    Text(model.link.host.isEmpty ? "Wi-Fi" : "Wi-Fi · \(model.link.host)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }
}

/// Large page title used at the top of each pane.
struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Rounded Liquid Glass card container.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
