import SwiftUI

struct SchedulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(title: "Schedules", subtitle: "Change the TV automatically at set times") {
                    Menu {
                        ForEach(ScheduleAction.allCases) { action in
                            Button(action.title) {
                                model.updateSettings { $0.schedules.append(ScheduleRule(action: action)) }
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .fixedSize()
                }

                if model.state.schedules.isEmpty {
                    GlassCard {
                        Text("No schedules yet. Examples: warm tint on at 21:00, turn the TV off at 23:30, open Ambient at 07:00.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(model.state.schedules.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { rule in
                    GlassCard {
                        HStack(spacing: 14) {
                            Toggle("", isOn: field(rule.id, \.enabled)).labelsHidden()
                            DatePicker("", selection: time(rule), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Picker("", selection: field(rule.id, \.action)) {
                                ForEach(ScheduleAction.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                            valuePicker(rule)
                            Spacer()
                            Button {
                                model.run(rule)
                            } label: {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Run now")
                            Button {
                                model.updateSettings { $0.schedules.removeAll { $0.id == rule.id } }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .toggleStyle(.switch)
                    }
                }

                Text("Schedules run every day while Ambient Control is open on this Mac. Turning the TV off needs Wi-Fi pairing (TV tab).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    @ViewBuilder private func valuePicker(_ rule: ScheduleRule) -> some View {
        switch rule.action {
        case .wallpaper:
            Picker("", selection: field(rule.id, \.value)) {
                ForEach(Array(BuiltInWallpaper.all.enumerated()), id: \.offset) { i, wp in Text(wp.name).tag(i) }
            }
            .labelsHidden()
            .frame(width: 120)
        case .brightness:
            Picker("", selection: field(rule.id, \.value)) {
                Text("Low").tag(0)
                Text("Medium").tag(1)
                Text("High").tag(2)
            }
            .labelsHidden()
            .frame(width: 120)
        default:
            EmptyView()
        }
    }

    private func time(_ rule: ScheduleRule) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                update(rule.id) { $0.hour = c.hour ?? 0; $0.minute = c.minute ?? 0 }
            }
        )
    }

    private func field<T>(_ id: UUID, _ kp: WritableKeyPath<ScheduleRule, T>) -> Binding<T> {
        Binding(get: { model.state.schedules.first { $0.id == id }![keyPath: kp] },
                set: { v in update(id) { $0[keyPath: kp] = v } })
    }

    private func update(_ id: UUID, _ change: (inout ScheduleRule) -> Void) {
        model.updateSettings { s in
            if let i = s.schedules.firstIndex(where: { $0.id == id }) { change(&s.schedules[i]) }
        }
    }
}
