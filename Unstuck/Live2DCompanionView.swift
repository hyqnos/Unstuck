import SwiftUI
import WebKit

/// The Live2D companion slot. Renders a Live2D Cubism model inside a transparent
/// WKWebView using the Cubism **Web** SDK — the lighter integration path (no native
/// C++/Metal bridge). Until you add the SDK + a licensed model (see docs/LIVE2D.md),
/// it shows a calm placeholder so nothing breaks.
///
/// To go live: bundle `Live2D/companion.html` (loading the Cubism Web SDK +
/// pixi-live2d-display + your model). This view auto-loads it when present.
struct Live2DCompanion: View {
    var body: some View {
        Live2DWebView()
            .frame(width: 112, height: 150)
            .accessibilityLabel(Text("Your companion"))
            .accessibilityHint(Text("Live2D character slot."))
    }
}

private struct Live2DWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        // Load your bundled model page if it exists; otherwise the placeholder.
        if let url = Bundle.main.url(forResource: "companion", withExtension: "html", subdirectory: "Live2D") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.loadHTMLString(Self.placeholderHTML, baseURL: nil)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static let placeholderHTML = """
    <html><head><meta name='viewport' content='width=device-width,initial-scale=1'>
    <style>
      html,body{margin:0;height:100%;background:transparent;display:flex;
        align-items:center;justify-content:center;font-family:-apple-system,monospace}
      .c{color:rgba(255,255,255,0.55);text-align:center;font-size:12px;line-height:1.5}
      .e{font-size:34px;filter:saturate(0.6)}
    </style></head>
    <body><div class='c'><div class='e'>🌀</div>live2d slot<br>
    <span style='font-size:9px;opacity:0.7'>add a model — see docs/LIVE2D.md</span></div></body></html>
    """
}
