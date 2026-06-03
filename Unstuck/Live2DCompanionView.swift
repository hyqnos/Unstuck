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
            web.loadHTMLString(Self.characterHTML, baseURL: nil)   // a basic constructed character
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    /// A basic Live2D-STYLE character built in SVG/CSS — breathes, blinks, sways. Not a
    /// real rigged `.moc3` (that needs the Cubism editor + an artist), but it gives the
    /// slot a living character until a real model is dropped in (see docs/LIVE2D.md).
    static let characterHTML = """
    <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>
    <style>
      html,body{margin:0;height:100%;background:transparent;overflow:hidden;
        display:flex;align-items:flex-end;justify-content:center}
      .stage{width:200px;height:260px;filter:drop-shadow(0 6px 14px rgba(0,200,170,.35))}
      .sway{transform-origin:100px 240px;animation:sway 6s ease-in-out infinite}
      .breathe{transform-origin:100px 240px;animation:breathe 3.4s ease-in-out infinite}
      @keyframes sway{0%,100%{transform:rotate(-2.5deg)}50%{transform:rotate(2.5deg)}}
      @keyframes breathe{0%,100%{transform:scale(1) translateY(0)}50%{transform:scale(1.035) translateY(-5px)}}
      .eye{transform-origin:center;transform-box:fill-box;animation:blink 4.8s infinite}
      .eye.b{animation-delay:.06s}
      @keyframes blink{0%,93%,100%{transform:scaleY(1)}96%{transform:scaleY(.08)}}
      .hair{transform-origin:100px 60px;animation:hairwave 4s ease-in-out infinite}
      @keyframes hairwave{0%,100%{transform:rotate(-2deg)}50%{transform:rotate(2.5deg)}}
    </style></head>
    <body>
    <svg class='stage' viewBox='0 0 200 260' xmlns='http://www.w3.org/2000/svg'>
     <defs>
      <radialGradient id='head' cx='42%' cy='34%' r='78%'>
       <stop offset='0%' stop-color='#9af7e0'/><stop offset='58%' stop-color='#46d9b8'/><stop offset='100%' stop-color='#2bb89a'/>
      </radialGradient>
      <linearGradient id='body' x1='0' y1='0' x2='0' y2='1'>
       <stop offset='0%' stop-color='#3fd0af'/><stop offset='100%' stop-color='#1f9e84'/>
      </linearGradient>
     </defs>
     <g class='sway'><g class='breathe'>
       <ellipse cx='100' cy='212' rx='54' ry='46' fill='url(#body)'/>
       <ellipse cx='54' cy='206' rx='13' ry='19' fill='#2bb89a'/>
       <ellipse cx='146' cy='206' rx='13' ry='19' fill='#2bb89a'/>
       <ellipse cx='34' cy='112' rx='14' ry='21' fill='#2bb89a'/>
       <ellipse cx='166' cy='112' rx='14' ry='21' fill='#2bb89a'/>
       <ellipse cx='100' cy='120' rx='74' ry='68' fill='url(#head)'/>
       <g class='hair' fill='#26a98e'>
         <path d='M100 54 q-12 -24 -28 -10 q15 3 17 17 z'/>
         <path d='M100 52 q5 -26 24 -14 q-15 4 -15 19 z'/>
         <ellipse cx='100' cy='58' rx='11' ry='13'/>
       </g>
       <ellipse cx='58' cy='140' rx='13' ry='9' fill='#ff8fb0' opacity='.5'/>
       <ellipse cx='142' cy='140' rx='13' ry='9' fill='#ff8fb0' opacity='.5'/>
       <g class='eye'><ellipse cx='72' cy='118' rx='15' ry='19' fill='#fff'/>
         <circle cx='74' cy='122' r='9' fill='#16312b'/><circle cx='78' cy='117' r='3.2' fill='#fff'/></g>
       <g class='eye b'><ellipse cx='128' cy='118' rx='15' ry='19' fill='#fff'/>
         <circle cx='126' cy='122' r='9' fill='#16312b'/><circle cx='130' cy='117' r='3.2' fill='#fff'/></g>
       <path d='M88 150 q12 13 24 0' stroke='#16312b' stroke-width='3' fill='none' stroke-linecap='round'/>
     </g></g>
    </svg>
    </body></html>
    """
}
