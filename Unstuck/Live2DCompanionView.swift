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
    private let mood = MoodDetector.shared
    private var tintHex: String {
        switch mood.mode {
        case .ready:      return "4CD999"
        case .hyperfocus: return "7280FF"
        case .lowBattery: return "FF9966"
        case .overwhelm:  return "99A8C7"
        }
    }
    var body: some View {
        Live2DWebView(tintHex: tintHex)       // glow recolours to the brain mode
            .frame(width: 112, height: 150)
            .accessibilityLabel(Text("Your companion"))
            .accessibilityHint(Text("Live2D character slot."))
    }
}

private struct Live2DWebView: UIViewRepresentable {
    let tintHex: String
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

    func updateUIView(_ web: WKWebView, context: Context) {
        web.evaluateJavaScript("window.setTint && window.setTint('#\(tintHex)')", completionHandler: nil)
    }

    /// A basic Live2D-STYLE character built in SVG/CSS — breathes, blinks, sways. Not a
    /// real rigged `.moc3` (that needs the Cubism editor + an artist), but it gives the
    /// slot a living character until a real model is dropped in (see docs/LIVE2D.md).
    static let characterHTML = """
    <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>
    <style>
      html,body{margin:0;height:100%;background:transparent;overflow:hidden;
        display:flex;align-items:center;justify-content:center}
      .stage{width:220px;height:270px}
      .glow{transform-origin:110px 132px;animation:pulse 2.6s ease-in-out infinite}
      @keyframes pulse{0%,100%{opacity:.45;transform:scale(1)}50%{opacity:.85;transform:scale(1.08)}}
      .creature{transform-origin:110px 200px;animation:float 3s ease-in-out infinite}
      @keyframes float{0%,100%{transform:translateY(2px) rotate(-2deg)}50%{transform:translateY(-9px) rotate(2deg)}}
      .orbit{transform-origin:110px 132px;animation:spin 9s linear infinite}
      @keyframes spin{to{transform:rotate(360deg)}}
      .twk{animation:tw 1.8s ease-in-out infinite}
      @keyframes tw{0%,100%{opacity:.3;transform:scale(.7)}50%{opacity:1;transform:scale(1.2)}}
      .lid{transform-origin:center;transform-box:fill-box;animation:wink 4.6s infinite}
      @keyframes wink{0%,90%,100%{transform:scaleY(0)}94%{transform:scaleY(1)}}
      .bolt{transform-origin:110px 56px;animation:zap 2.4s ease-in-out infinite}
      @keyframes zap{0%,100%{transform:rotate(-4deg)}50%{transform:rotate(5deg)}}
    </style></head>
    <body>
    <svg class='stage' viewBox='0 0 220 270' xmlns='http://www.w3.org/2000/svg'>
     <defs>
      <radialGradient id='bodyG' cx='40%' cy='32%' r='80%'>
       <stop offset='0%' stop-color='#7df9ff'/><stop offset='45%' stop-color='#36c6ff'/><stop offset='100%' stop-color='#7a4dff'/>
      </radialGradient>
      <radialGradient id='aura' cx='50%' cy='50%' r='50%'>
       <stop offset='0%' stop-color='#4ad9ff' stop-opacity='.7'/><stop offset='100%' stop-color='#4ad9ff' stop-opacity='0'/>
      </radialGradient>
      <linearGradient id='boltG' x1='0' y1='0' x2='0' y2='1'>
       <stop offset='0%' stop-color='#fff27a'/><stop offset='100%' stop-color='#ffb13d'/>
      </linearGradient>
     </defs>
     <circle class='glow' cx='110' cy='132' r='92' fill='url(#aura)'/>
     <g class='orbit'>
       <path class='twk' d='M196 132 l3 7 7 3 -7 3 -3 7 -3 -7 -7 -3 7 -3 z' fill='#bff6ff'/>
       <path class='twk' style='animation-delay:.6s' d='M24 120 l2.4 5 5 2.4 -5 2.4 -2.4 5 -2.4 -5 -5 -2.4 5 -2.4 z' fill='#cfa8ff'/>
       <path class='twk' style='animation-delay:1.1s' d='M110 36 l2 4.5 4.5 2 -4.5 2 -2 4.5 -2 -4.5 -4.5 -2 4.5 -2 z' fill='#fff27a'/>
     </g>
     <g class='creature'>
       <path d='M110 60 C56 60 44 104 44 138 C44 184 72 214 110 214 C148 214 176 184 176 138 C176 104 164 60 110 60 Z'
             fill='url(#bodyG)' stroke='#bdf6ff' stroke-opacity='.35' stroke-width='1.5'/>
       <path class='bolt' d='M104 34 l16 0 -8 14 12 0 -22 26 6 -18 -10 0 z' fill='url(#boltG)' stroke='#fff' stroke-opacity='.3' stroke-width='1'/>
       <g transform='rotate(-8 84 128)'>
         <ellipse cx='84' cy='128' rx='16' ry='20' fill='#0c1430'/>
         <circle cx='88' cy='132' r='9.5' fill='#7df9ff'/><circle cx='91' cy='127' r='3.6' fill='#fff'/>
         <rect class='lid' x='66' y='106' width='36' height='44' rx='14' fill='url(#bodyG)'/>
       </g>
       <g transform='rotate(8 136 128)'>
         <ellipse cx='136' cy='128' rx='16' ry='20' fill='#0c1430'/>
         <circle cx='132' cy='132' r='9.5' fill='#7df9ff'/><circle cx='135' cy='127' r='3.6' fill='#fff'/>
       </g>
       <path d='M92 162 q16 16 40 4' stroke='#0c1430' stroke-width='4' fill='none' stroke-linecap='round'/>
     </g>
    </svg>
    <script>
      window.setTint=function(h){document.querySelectorAll('#aura stop').forEach(function(s){s.setAttribute('stop-color',h)});document.querySelectorAll('.twk').forEach(function(t){t.setAttribute('fill',h)})};
    </script>
    </body></html>
    """
}
