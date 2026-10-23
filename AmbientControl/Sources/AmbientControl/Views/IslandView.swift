import SwiftUI

struct IslandView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var title = "Dinner is ready"
    @ViewState private var text = "Come to the table"
    @ViewState private var icon: IslandIcon = .food
    @ViewState private var color: IslandColor = .orange
    @ViewState private var seconds = 8
    @ViewState private var replay = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Dynamic Island", subtitle: "Notifications and live timers at the top of the TV")

                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 20) {
                        composer
                        presets
                    }
                    .frame(maxWidth: 520)

                    VStack(alignment: .leading, spacing: 20) {
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Preview").font(.headline).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Replay", systemImage: "arrow.counterclockwise") { replay += 1 }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)
                                }
                                IslandStage(mode: .expanded(title: title, text: text, icon: icon, color: color.color),
                                            replay: replay)
                            }
                        }
                        TimerCard()
                    }
                }
            }
            .padding(32)
        }
    }

    private var composer: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Notification", systemImage: "bell.badge").font(.headline)
                field("Title", text: $title)
                field("Message", text: $text)

                Text("Icon").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 10), count: 6), alignment: .leading, spacing: 10) {
                    ForEach(IslandIcon.allCases) { i in
                        Button {
                            icon = i
                        } label: {
                            Image(systemName: i.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(i == icon ? color.color : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Colour").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(IslandColor.allCases) { c in
                        Button {
                            color = c
                        } label: {
                            Circle()
                                .fill(c.color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white, lineWidth: c == color ? 2.5 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Picker("Show for", selection: $seconds) {
                        Text("5 s").tag(5)
                        Text("8 s").tag(8)
                        Text("12 s").tag(12)
                        Text("20 s").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Spacer()
                    Button("Send to TV", systemImage: "paperplane.fill") {
                        model.sendNotification(title: title, text: text, icon: icon, color: color, seconds: seconds)
                        replay += 1
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var presets: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("One-tap", systemImage: "bolt.fill").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(IslandPreset.all) { p in
                        Button {
                            title = p.title
                            text = p.text
                            icon = p.icon
                            color = p.color
                            model.sendNotification(title: p.title, text: p.text, icon: p.icon, color: p.color, seconds: seconds)
                            replay += 1
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: p.icon.symbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(p.color.color))
                                Text(p.title).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct TimerCard: View {
    @Environment(AppModel.self) private var model
    @ViewState private var name = ""
    @ViewState private var minutes = 10

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Live Timer", systemImage: "timer").font(.headline)

                if let end = model.timerEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
                        HStack(spacing: 16) {
                            IslandStage(mode: .compact(remaining: left), replay: 0)
                                .frame(maxWidth: 320)
                            Spacer()
                            Button("Cancel", systemImage: "xmark") { model.cancelTimer() }
                                .buttonStyle(.glass)
                        }
                    }
                } else {
                    Text("Counts down in the TV's Dynamic Island and announces when it's done, like the iPhone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Name (e.g. Pizza)", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach([1, 5, 10, 15, 30, 60], id: \.self) { m in
                                Button("\(m) min") { minutes = m }
                                    .buttonStyle(.plain)
                                    .font(.callout.weight(m == minutes ? .bold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassEffect(m == minutes ? .regular.tint(.orange.opacity(0.5)).interactive() : .regular.interactive(), in: .capsule)
                            }
                        }
                    }
                    HStack {
                        Stepper("\(minutes) minutes", value: $minutes, in: 1...240)
                        Spacer()
                        Button("Start", systemImage: "play.fill") {
                            model.startTimer(title: name, seconds: minutes * 60)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                    }
                }
            }
        }
    }
}

/// SwiftUI replica of the TV's island, on a small wallpaper, for previews.
struct IslandStage: View {
    enum Mode: Equatable {
        case expanded(title: String, text: String, icon: IslandIcon, color: Color)
        case compact(remaining: Int)
    }

    let mode: Mode
    let replay: Int
    @ViewState private var open = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.6), Color(red: 0.4, green: 0.2, blue: 0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            island
                .padding(.top, 14)
        }
        .frame(height: isCompact ? 76 : 150)
        .clipShape(.rect(cornerRadius: 16))
        .onAppear { animateIn() }
        .onChange(of: replay) { animateIn() }
    }

    private var isCompact: Bool {
        if case .compact = mode { return true }
        return false
    }

    @ViewBuilder private var island: some View {
        switch mode {
        case let .expanded(title, text, icon, color):
            HStack(spacing: 14) {
                Image(systemName: icon.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(color))
                    .scaleEffect(open ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? text : title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if !title.isEmpty && !text.isEmpty {
                        Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                    }
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("now").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            }
            .opacity(open ? 1 : 0)
            .padding(.horizontal, 14)
            .frame(width: open ? 420 : 110, height: open ? 80 : 30)
            .background(.black, in: .capsule)

        case let .compact(remaining):
            HStack {
                Image(systemName: "timer").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(String(format: remaining >= 3600 ? "%d:%02d:%02d" : "%d:%02d",
                            arguments: remaining >= 3600 ? [remaining / 3600, (remaining % 3600) / 60, remaining % 60]
                                                         : [remaining / 60, remaining % 60]))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .frame(width: 170, height: 34)
            .background(.black, in: .capsule)
        }
    }

    private func animateIn() {
        open = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.15)) { open = true }
    }
}
