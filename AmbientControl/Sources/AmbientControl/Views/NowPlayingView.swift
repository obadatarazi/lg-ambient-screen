import SwiftUI

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var message = ""
    @ViewState private var showRemote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Now Playing", subtitle: "Live preview of your TV") {
                    Button {
                        Task { await model.openOnTV() }
                    } label: {
                        Label("Open on TV", systemImage: "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(model.tv.busy != nil)
                }

                if model.tvPending {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                        Text("The TV is showing something else. Your changes are saved and will appear when Ambient opens.")
                            .font(.callout)
                        Spacer()
                        Button("Open Now") { Task { await model.openOnTV() } }
                            .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 18))
                }

                // Remote controls stay faint (just to show where they are) and come fully
                // forward while the pointer is over the preview. Mac app only, not the TV.
                TVPreview()
                    .overlay(alignment: .bottom) {
                        ZStack(alignment: .bottom) {
                            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 150)
                                .opacity(showRemote ? 1 : 0)
                                .allowsHitTesting(false)
                            RemoteBar()
                                .padding(.bottom, 22)
                                .opacity(showRemote ? 1 : 0.3)
                                .scaleEffect(showRemote ? 1 : 0.88, anchor: .bottom)
                        }
                        .clipShape(.rect(cornerRadius: 22))
                    }
                    .onHover { inside in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showRemote = inside }
                    }

                HStack(alignment: .top, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Send to Dynamic Island", systemImage: "capsule.fill")
                                .font(.headline)
                            Text("Pops up at the top of the TV screen for 8 seconds.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("Dinner is ready 🍝", text: $message)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .glassEffect(.regular, in: .capsule)
                                    .onSubmit(sendMessage)
                                Button("Send", systemImage: "paperplane.fill", action: sendMessage)
                                    .buttonStyle(.glassProminent)
                                    .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    GlassCard {
                        NowShowingSummary()
                    }
                }
            }
            .padding(32)
        }
    }

    private func sendMessage() {
        model.send(message: message)
        message = ""
    }
}

/// Floating remote control over the preview, Liquid Glass buttons that merge together.
struct RemoteBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                remote("backward.fill", "Previous quote", "prevQuote")
                remote("forward.fill", "Next quote", "nextQuote")
                remote("playpause.fill", "Pause / resume", "togglePause")
                remote("photo.fill", "Next wallpaper", "nextWallpaper")
                remote("sun.max.fill", "Brightness", "brightness")
            }
        }
    }

    private func remote(_ symbol: String, _ help: String, _ action: String) -> some View {
        Button {
            model.send(command: action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }
}

struct NowShowingSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("On the TV", systemImage: "tv")
                .font(.headline)
            if let media = model.state.media, media.isScreen {
                row("rectangle.on.rectangle", "Screen Share", media.name)
            } else if let media = model.state.media {
                row(media.isVideo ? "film" : "photo", media.name, "Fullscreen")
            } else if !model.state.playlist.isEmpty {
                row("list.bullet", "Playlist", "\(model.state.playlist.count) items rotating")
            } else if let wp = model.state.customWallpaper {
                row("sparkles", "Ambient", "Your wallpaper: \(wp.name)")
            } else {
                let name = model.state.wallpaper >= 0
                    ? BuiltInWallpaper.all[model.state.wallpaper % BuiltInWallpaper.all.count].name
                    : "rotating"
                row("sparkles", "Ambient", "Clock, widgets, wallpaper: \(name)")
            }
            if model.isPlaying {
                Button("Back to Ambient", systemImage: "xmark") { model.stopMedia() }
                    .buttonStyle(.glass)
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(.accentColor.opacity(0.35)), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
