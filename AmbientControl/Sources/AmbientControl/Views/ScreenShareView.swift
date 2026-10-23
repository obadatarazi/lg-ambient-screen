import SwiftUI

struct ScreenShareView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var screen = model.screen

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Screen Share", subtitle: "Show a Mac display on the TV") {
                    if model.screen.isSharing {
                        Button("Stop Sharing", systemImage: "stop.fill") {
                            Task { await model.stopScreenShare() }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                        .controlSize(.large)
                    } else {
                        Button("Weather App", systemImage: "cloud.sun") {
                            Task { await model.showWeatherApp() }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .help("Show the Mac's Weather app on the TV")
                        Button("Share to TV", systemImage: "rectangle.on.rectangle") {
                            Task { await model.startScreenShare() }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(model.screen.selected == nil)
                    }
                }

                if model.screen.isSharing {
                    LiveBanner()
                }

                if model.screen.permissionDenied {
                    GlassCard {
                        HStack(spacing: 16) {
                            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Screen recording permission needed").font(.headline)
                                Text("Turn on Ambient Control in Privacy & Security → Screen & System Audio Recording, then quit and reopen the app.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open Settings") { ScreenShare.openPrivacySettings() }
                                .buttonStyle(.glass)
                        }
                    }
                } else if let error = model.screen.error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }

                Text(model.screen.displays.count > 1 ? "Choose a display" : "Display")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 20)], spacing: 20) {
                    ForEach(model.screen.displays) { d in
                        DisplayCard(display: d, selected: d.id == model.screen.selectedID) {
                            model.screen.selectedID = d.id
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Options", systemImage: "slider.horizontal.3").font(.headline)
                        Picker("Quality", selection: $screen.quality) {
                            ForEach(ScreenShare.Quality.allCases) { q in
                                Text("\(q.rawValue) (\(q.detail))").tag(q)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Play the Mac's sound on the TV speakers", isOn: $screen.playSound)
                        Toggle("Mute the Mac while sharing", isOn: $screen.muteMac)
                            .disabled(!screen.playSound || model.screen.isSharing)
                            .padding(.leading, 20)
                        Toggle("Show mouse pointer", isOn: $screen.showCursor)
                        Toggle("Hide the Ambient Control window from the TV", isOn: $screen.hideThisApp)
                        Text("Sharing goes straight from this Mac to the TV over your Wi-Fi, so internet speed doesn't matter. Quality adjusts by itself when the Wi-Fi gets busy. Options apply the next time you start sharing. The picture runs about 2 seconds behind, so it suits slides, videos, photos and browsing more than games.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .disabled(model.screen.isSharing)
                }
            }
            .padding(32)
        }
        .task {
            await model.screen.refreshDisplays()
        }
    }
}

private struct LiveBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(.red).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Live on TV: \(model.screen.selected?.name ?? "Mac screen")")
                    .font(.headline)
                Text(model.screen.fps > 0 ? status : "Waiting for the TV to connect…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if model.screen.playSound {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .help("The Mac's sound plays on the TV")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular.tint(.red.opacity(0.2)), in: .rect(cornerRadius: 18))
    }

    private var status: String {
        let s = model.screen
        var parts = ["\(s.fps) fps", "Auto quality \(mbps(s.targetKbps))"]
        if s.linkKbps > 0 { parts.append("Wi-Fi \(mbps(s.linkKbps))") }
        return parts.joined(separator: " · ")
    }

    private func mbps(_ kbps: Int) -> String { String(format: "%.1f Mbit/s", Double(kbps) / 1000) }
}

private struct DisplayCard: View {
    let display: ScreenShare.Display
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let t = display.thumbnail {
                        Image(nsImage: t).resizable().scaledToFit()
                    } else {
                        Image(systemName: "display").font(.system(size: 40)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(selected ? Color.accentColor : .white.opacity(0.12), lineWidth: selected ? 3 : 1)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("\(display.width) × \(display.height)\(display.isMain ? " · Main" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }
}
