import ServiceManagement
import SwiftUI

@main
struct AmbientControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var model = AppModel()

    var body: some Scene {
        WindowGroup("Ambient Control", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 720)
                // ambientcontrol://youtube?url=<link>  plays a YouTube video on the TV
                .onOpenURL { url in
                    guard url.host == "youtube",
                          let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "url" || $0.name == "v" })?.value else { return }
                    Task { await model.playYouTube(link) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)

        MenuBarExtra("Ambient Control", systemImage: "tv.badge.wifi") {
            MenuBarView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running as a bare SwiftPM binary needs this to get a Dock icon and focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    // Keep serving the TV after the window is closed; quit from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @ViewState private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(model.tvConnected ? "TV connected" : "TV not connected")
        Divider()
        Button("Open Ambient Control") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Open on TV") { Task { await model.openOnTV() } }
        Divider()
        Button("Next Wallpaper") { model.send(command: "nextWallpaper") }
        Button("Next Quote") { model.send(command: "nextQuote") }
        Button("Pause / Resume") { model.send(command: "togglePause") }
        if model.screen.isSharing {
            Button("Stop Screen Share") { Task { await model.stopScreenShare() } }
        } else {
            Button("Share Screen to TV") { Task { await model.startScreenShare() } }
        }
        if model.isPlaying {
            Button("Stop Media") { model.stopMedia() }
        }
        Divider()
        Toggle("Open at Login", isOn: $openAtLogin)
            .onChange(of: openAtLogin) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
