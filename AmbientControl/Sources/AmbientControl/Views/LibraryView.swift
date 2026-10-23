import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var importing = false
    @ViewState private var addingStream = false
    @ViewState private var dropTargeted = false

    private var items: [MediaItem] { model.library + model.streams }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Library", subtitle: "Drop photos and videos here, then send them to the TV") {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            Button("Add Stream", systemImage: "link") { addingStream = true }
                                .buttonStyle(.glass)
                            Button("Import", systemImage: "plus") { importing = true }
                                .buttonStyle(.glassProminent)
                        }
                    }
                    .controlSize(.large)
                }

                if !model.state.playlist.isEmpty {
                    PlaylistStrip()
                }

                if items.isEmpty {
                    ContentUnavailableView {
                        Label("No media yet", systemImage: "photo.stack")
                    } description: {
                        Text("Drag photos or videos into this window, or click Import.\nFor videos, H.264 MP4 at 1080p plays best on this TV.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 20)], spacing: 22) {
                        ForEach(items) { item in
                            MediaTile(item: item)
                        }
                    }
                }
            }
            .padding(32)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls) > 0
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.importFiles(urls) }
        }
        .sheet(isPresented: $addingStream) {
            AddStreamSheet()
        }
    }
}

struct MediaTile: View {
    @Environment(AppModel.self) private var model
    let item: MediaItem
    @ViewState private var hovering = false

    var body: some View {
        let current = model.isCurrent(item)
        let isWallpaper = model.state.customWallpaper?.name == item.name

        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                MediaThumb(item: item)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 18))

                if hovering {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            tileButton("play.fill", "Show on TV") { model.show(item) }
                            tileButton("text.badge.plus", "Add to playlist") { model.addToPlaylist(item) }
                            if !item.isVideo && !item.isStream {
                                tileButton("photo.artframe", "Use as wallpaper") { model.setCustomWallpaper(item) }
                            }
                            tileButton("trash", "Delete") { model.delete(item) }
                        }
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    if item.isStream { badge("Stream", "dot.radiowaves.left.and.right") }
                    else if item.isVideo { badge("Video", "film") }
                    if current { badge("On TV", "tv") }
                    if isWallpaper { badge("Wallpaper", "sparkles") }
                }
                .padding(10)
            }
            .overlay {
                if current {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(item.isStream ? item.url : ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hovering = h } }
        .contextMenu {
            Button("Show on TV") { model.show(item) }
            Button("Add to Playlist") { model.addToPlaylist(item) }
            if !item.isVideo && !item.isStream {
                Button("Use as Wallpaper") { model.setCustomWallpaper(item) }
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(item) }
        }
    }

    private func tileButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }

    private func badge(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
    }
}

struct MediaThumb: View {
    @Environment(AppModel.self) private var model
    let item: MediaItem
    @ViewState private var image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.6), .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: item.isStream ? "dot.radiowaves.left.and.right" : (item.isVideo ? "film" : "photo"))
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .task(id: item.url) {
            guard let url = model.fileURL(for: item) else { return }
            image = await ImageTools.thumbnail(for: url, size: CGSize(width: 480, height: 270))
        }
    }
}

struct PlaylistStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Playlist", systemImage: "list.bullet")
                        .font(.headline)
                    Text("Changes every \(model.state.intervalSec) s")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop", systemImage: "stop.fill") { model.stopMedia() }
                        .buttonStyle(.glass)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.state.playlist.enumerated()), id: \.element.id) { i, item in
                            HStack(spacing: 8) {
                                Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(item.name).font(.callout).lineLimit(1)
                                Button {
                                    model.removeFromPlaylist(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }
        }
    }
}

struct AddStreamSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var url = ""
    @ViewState private var name = ""
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Stream").font(.title2.weight(.bold))
            Text("A direct link to an MP4 video or an image (http/https). The TV loads it directly.\nPage links such as YouTube or Netflix will not work.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Name (optional)", text: $name)
            TextField("https://example.com/video.mp4", text: $url)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if model.addStream(url, name: name) {
                        dismiss()
                    } else {
                        error = "Enter a valid http:// or https:// link."
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 460)
    }
}
