import SwiftUI

struct TVView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var tv = model.tv

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "TV", subtitle: "Your LG webOS TV in Developer Mode") {
                    if let busy = model.tv.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(busy).font(.callout)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                    }
                }

                WiFiRemoteCard()

                HStack(alignment: .top, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Image(systemName: "tv")
                                    .font(.system(size: 30))
                                    .frame(width: 62, height: 62)
                                    .glassEffect(.regular.tint(statusColor.opacity(0.4)), in: .rect(cornerRadius: 16))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.tv.model).font(.title2.weight(.bold))
                                    Text(statusText).font(.callout).foregroundStyle(statusColor)
                                }
                            }
                            if !model.tv.info.isEmpty {
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                                    infoRow("webOS SDK", model.tv.info["sdkVersion"])
                                    infoRow("Firmware", model.tv.info["firmwareVersion"])
                                    infoRow("Board", model.tv.info["boardType"])
                                }
                                .font(.callout)
                            }
                            HStack {
                                Text("ares device")
                                    .foregroundStyle(.secondary)
                                TextField("lg-tv", text: $tv.deviceName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                            }
                            .font(.callout)

                            GlassEffectContainer(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button("Launch", systemImage: "play.fill") { Task { await model.openOnTV() } }
                                        .buttonStyle(.glassProminent)
                                    Button("Close", systemImage: "xmark") { Task { await model.tv.close() } }
                                        .buttonStyle(.glass)
                                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.tv.refresh() } }
                                        .buttonStyle(.glass)
                                }
                            }
                            .disabled(model.tv.busy != nil)

                            if let ipk = model.paths.ipk {
                                Button("Install / Update TV App", systemImage: "square.and.arrow.down") {
                                    Task { await model.tv.install(ipk: ipk) }
                                }
                                .buttonStyle(.glass)
                                .disabled(model.tv.busy != nil)
                            }

                            if !model.tv.lastResult.isEmpty {
                                Text(model.tv.lastResult)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Connection", systemImage: "wifi").font(.headline)
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                    infoRow("This Mac", model.serverAddress)
                                    infoRow("Server", model.serverError == nil ? "Running" : "Error")
                                    infoRow("TV app", tvSeenText)
                                    if let ip = model.tvClientIP { infoRow("TV address", ip) }
                                }
                                .font(.callout)
                            }
                            if let err = model.serverError {
                                Text(err).font(.callout).foregroundStyle(.red)
                            }
                            Text("Only needed to stream photos and videos from this Mac. Settings reach the TV over the Wi-Fi remote and stay saved on the TV.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Good to know", systemImage: "info.circle").font(.headline)
                        tip("The TV keeps your last settings and wallpaper photo, so it runs fine when this Mac is off or away. Photos and videos you stream need the Mac nearby.")
                        tip("LG's Developer Mode session expires unless extended in the Developer Mode app. When it expires, apps installed through it are removed; use Install to put it back.")
                        tip("Video plays best as H.264 MP4 at 1080p or lower. HEVC, 4K and .mov files may not play on this 2017 TV.")
                        if !model.tv.aresInstalled {
                            tip("ares-cli was not found. Install it with: npm install -g @webos-tools/cli")
                        }
                    }
                }
            }
            .padding(32)
        }
    }

    private var statusColor: Color {
        switch model.tv.reachable {
        case true?: .green
        case false?: .orange
        case nil: .secondary
        }
    }

    private var statusText: String {
        switch model.tv.reachable {
        case true?: model.tv.appRunning == true ? "Online · Ambient Screen running" : "Online"
        case false?: "Not reachable"
        case nil: "Not checked yet"
        }
    }

    private var tvSeenText: String {
        guard let seen = model.tvLastSeen else { return "Not connected yet" }
        let s = Int(Date().timeIntervalSince(seen))
        return s < 10 ? "Connected" : "Last seen \(s / 60 > 0 ? "\(s / 60) min" : "\(s) s") ago"
    }

    private func infoRow(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value ?? "—").textSelection(.enabled)
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Pairing and status for direct Wi-Fi control (LG remote API).
struct WiFiRemoteCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var link = model.link

        GlassCard {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "wifi")
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 62, height: 62)
                    .glassEffect(.regular.tint(color.opacity(0.4)), in: .rect(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Wi-Fi Remote").font(.title2.weight(.bold))
                    Text(statusText).font(.callout).foregroundStyle(color)

                    HStack(spacing: 10) {
                        Text("TV address").foregroundStyle(.secondary)
                        TextField("192.168.1.x", text: $link.host)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        Button("Find TV", systemImage: "magnifyingglass") {
                            Task { await model.link.discover(subnetOf: model.lanIP) }
                        }
                        .buttonStyle(.glass)
                        .disabled(model.link.searching)
                        if model.link.searching { ProgressView().controlSize(.small) }
                    }
                    .font(.callout)

                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            if model.link.paired {
                                Button("Reconnect", systemImage: "arrow.clockwise") {
                                    Task { await model.link.connect() }
                                }
                                .buttonStyle(.glass)
                                Button("Forget TV", systemImage: "xmark") { model.link.forget() }
                                    .buttonStyle(.glass)
                            } else {
                                Button("Pair with TV", systemImage: "link") {
                                    Task { await model.pairTV() }
                                }
                                .buttonStyle(.glassProminent)
                                .disabled(model.link.status == .connecting || model.link.status == .waitingForApproval)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var color: Color {
        switch model.link.status {
        case .ready: .green
        case .waitingForApproval, .connecting: .orange
        case .failed: .red
        case .idle: .secondary
        }
    }

    private var statusText: String {
        switch model.link.status {
        case .ready: return "Connected. Changes go straight to the TV while Ambient is open."
        case .connecting: return "Connecting…"
        case .waitingForApproval: return "Look at the TV and choose Accept with the remote."
        case .failed(let why): return why
        case .idle:
            return model.link.paired
                ? "Paired. Connects automatically when the TV is on."
                : "Pair once to control the TV over Wi-Fi. The TV will ask you to accept."
        }
    }
}
