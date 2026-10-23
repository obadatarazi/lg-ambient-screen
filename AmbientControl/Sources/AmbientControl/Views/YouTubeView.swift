import SwiftUI

struct YouTubeView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var input = ""
    @ViewState private var info: (title: String, author: String)?
    @ViewState private var playing = false
    @ViewState private var dropTargeted = false

    private var videoID: String? { YouTube.videoID(from: input) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "YouTube", subtitle: "Paste a link: it plays fullscreen on the TV with sound, right inside Ambient") {
                    HStack(spacing: 12) {
                        Picker("Quality", selection: Binding(get: { model.youtubeQuality }, set: { model.youtubeQuality = $0 })) {
                            ForEach(YouTubeStreamer.Quality.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                        .help("720p suits most home internet. Use 480p if videos pause to load.")
                        if model.state.media?.isYouTube == true {
                            Button("Stop", systemImage: "stop.fill") { model.stopMedia() }
                                .buttonStyle(.glass)
                        }
                    }
                    .controlSize(.large)
                }

                linkBar

                if let id = videoID {
                    pendingCard(id)
                }

                if !model.youtubeRecents.isEmpty {
                    Text("Recently played").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 18)], spacing: 18) {
                        ForEach(model.youtubeRecents) { v in
                            RecentVideoTile(video: v) { play(v.id) }
                        }
                    }
                }
            }
            .padding(32)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, YouTube.videoID(from: url.absoluteString) != nil else { return false }
            input = url.absoluteString
            play(input)
            return true
        } isTargeted: { dropTargeted = $0 }
        .task(id: videoID) {
            info = nil
            guard let id = videoID else { return }
            model.prefetchYouTube(id)
            info = await YouTube.info(for: id)
        }
    }

    private var linkBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            TextField("Paste a YouTube link", text: $input)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit { play(input) }
            if input.isEmpty {
                Button("Paste", systemImage: "doc.on.clipboard") {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    input = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("Play on TV", systemImage: "play.fill") { play(input) }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .disabled(videoID == nil || playing)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
    }

    private func pendingCard(_ id: String) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 18) {
                AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.black.opacity(0.3)
                }
                .frame(width: 220, height: 124)
                .clipShape(.rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text(info?.title ?? "YouTube video").font(.title3.weight(.semibold)).lineLimit(2)
                    if let author = info?.author, !author.isEmpty {
                        Text(author).font(.callout).foregroundStyle(.secondary)
                    }
                    if playing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(model.youtubeStatus ?? "Preparing…").font(.callout)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func play(_ link: String) {
        guard !playing else { return }
        playing = true
        Task {
            if await model.playYouTube(link) { input = "" }
            playing = false
        }
    }
}

private struct RecentVideoTile: View {
    @Environment(AppModel.self) private var model
    let video: YouTubeVideo
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    AsyncImage(url: video.thumbnail) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.black.opacity(0.3)
                    }
                    if hovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .glassEffect(.regular.tint(.red.opacity(0.6)), in: .circle)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))

                Text(video.title).font(.callout.weight(.semibold)).lineLimit(2)
                if !video.author.isEmpty {
                    Text(video.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hovering = h } }
        .contextMenu {
            Button("Play on TV", action: action)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("https://youtu.be/\(video.id)", forType: .string)
            }
            Divider()
            Button("Remove", role: .destructive) { model.forgetYouTube(video) }
        }
    }
}
