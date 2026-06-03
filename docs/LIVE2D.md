# Adding a Live2D companion (the drop-in slot)

The companion supports a **Live2D** character via `CompanionCharacter.live2d`. The
plumbing is built (`Live2DCompanionView.swift`, a transparent `WKWebView`); it shows
a calm placeholder until you add the SDK + a model. This is the **lighter** path —
the Cubism **Web** SDK in a web view — so there's no native C++/Metal bridge.

> **Licensing — read first.** Live2D's free *sample* models and "Free Material"
> assets are free for individuals and small studios, but have **commercial-revenue
> conditions** (above a threshold you need a paid Live2D license). Unstuck plans to
> monetize and ships to students, so **verify the current terms yourself** before
> relying on a model — and check the specific model's license. Claude did **not**
> download or bundle any model; that's your step, as the licensed party.

## Steps

1. **Register + pick a free model** at <https://www.live2d.com/en/> (e.g. the sample
   models — Hiyori, Haru, Mark, Natori…). Download the model folder (it contains
   `*.model3.json`, `*.moc3`, textures, `*.physics3.json`, `*.motion3.json`).

2. **Get the Web runtime.** You need the **Cubism Core for Web** (`live2dcubismcore.min.js`,
   from the Cubism SDK for Web) plus a renderer such as **pixi.js** +
   **pixi-live2d-display**. (All loadable as local files or via CDN inside the page.)

3. **Create `Unstuck/Live2D/companion.html`** — a tiny page with a transparent
   `<canvas>` that loads the Core JS + pixi + your model and centers it. Add the
   `Live2D/` folder to the **Unstuck** target so it ships in the bundle.
   `Live2DCompanionView` auto-loads `companion.html` from `Live2D/` when present
   (falling back to the placeholder otherwise).

4. **Transparent background.** In the page set `body{background:transparent}` and the
   PIXI app `backgroundAlpha: 0`; the web view is already transparent + non-scrolling.

5. **(Optional) react to app events.** Post `window.webkit.messageHandlers…` hooks, or
   evaluate JS from Swift on `.taskCompleted` / mood change to trigger a model motion
   (e.g. a happy expression on completion). Mirrors what the native creatures do.

## Notes
- Keep the model small (one model, a couple of motions) — it runs continuously in a
  corner; watch battery (the native creatures are 30fps-capped for this reason).
- Swapping back to a native character (`lion` / `fox` / `bear` / `orb`) always works
  even with no model present, so the app never depends on the Live2D asset.
- The character picker lives on the companion: **long-press it** to choose.
