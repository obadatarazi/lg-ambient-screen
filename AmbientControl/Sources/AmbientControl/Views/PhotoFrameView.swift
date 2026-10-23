import SwiftUI

struct PhotoFrameView: View {
    @Environment(AppModel.self) private var model

    private var photoCount: Int { model.library.filter { $0.type == "image" }.count }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PaneHeader(title: "Photo Frame", subtitle: "Turn the TV into a digital photo frame")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Start", systemImage: "play.rectangle.on.rectangle").font(.headline)
                            Button {
                                model.startPhotoFrame()
                            } label: {
                                Label("All Library Photos (\(photoCount))", systemImage: "photo.stack")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(photoCount == 0)
                            Button {
                                chooseFolder()
                            } label: {
                                Label("Choose a Folder…", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            Text("Photos from a folder are copied into the Library, so they keep working when the folder is gone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if model.isPlaying {
                                Button("Stop and go back to Ambient", systemImage: "stop.fill", role: .destructive) {
                                    model.stopMedia()
                                }
                            }
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Options", systemImage: "slider.horizontal.3").font(.headline)
                            Toggle("Shuffle", isOn: model.setting(\.photoFrame.shuffle))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Show each photo for \(duration(model.state.photoFrame.seconds))")
                                Slider(value: Binding(
                                    get: { Double(model.state.photoFrame.seconds) },
                                    set: { v in model.updateSettings { $0.photoFrame.seconds = Int(v) } }
                                ), in: 5...600, step: 5)
                            }
                            Toggle("Small clock in the corner", isOn: model.setting(\.photoFrame.cornerClock))
                            Toggle("Show the clock at all", isOn: model.setting(\.clockOverMedia))
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(32)
            }
            .frame(width: 520)

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview").font(.headline).foregroundStyle(.secondary)
                TVPreview(cornerRadius: 18)
            }
            .padding(.top, 104)
            .padding(.trailing, 32)
        }
    }

    private func duration(_ s: Int) -> String {
        s < 60 ? "\(s) seconds" : (s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder of photos"
        if panel.runModal() == .OK, let url = panel.url {
            model.startPhotoFrame(folder: url)
        }
    }
}
