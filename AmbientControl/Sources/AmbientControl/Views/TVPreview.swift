import SwiftUI
import WebKit

/// Live preview: runs the real TV app in a WKWebView against this Mac's server.
struct TVPreview: View {
    @Environment(AppModel.self) private var model
    var cornerRadius: CGFloat = 22

    var body: some View {
        Group {
            if model.paths.tvAppDir != nil {
                WebView(url: model.previewURL)
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: "tv.slash",
                                       description: Text("The TV app files were not bundled with this build."))
                    .background(.black)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

private struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    /// The server may still be starting when the first preview loads: retry quietly.
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { webView.reload() }
        }
    }
}
