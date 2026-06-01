# Unstuck

**A no-label brain tool for iOS.** It helps you capture thoughts, manage time, break things
down, and get moving when you're stuck — by giving your mind a place to live *outside* your
head: a spatial map you can see, fill, and breathe with.

Unstuck isn't a productivity app (those carry shame baggage). It's a **thinking space** — a
"brain" you externalize into. It never tells you what to do. It shows you your own patterns,
your own data, and your own words from a good day, and lets the "oh" land on its own.

> Built by and for a brain that gets overwhelmed by lists and lights up at a map. The app is
> marketed through relatable scenarios ("ever open the fridge and forget why?"), never through
> diagnosis or clinical language. There are no labels anywhere in it.

---

## Table of contents

- [The core idea](#the-core-idea)
- [Design constraints](#design-constraints-non-negotiable)
- [The systems](#the-systems)
- [Notable algorithms](#notable-algorithms)
- [Gesture vocabulary](#gesture-vocabulary)
- [The sensory dial](#the-sensory-dial)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Build & run](#build--run)
- [Privacy](#privacy)
- [Status & roadmap](#status--roadmap)

---

## The core idea

Your thoughts don't live in a list — they live in a *space*. Unstuck mirrors that.

**The brain map** is the home screen: a spatial canvas of clusters on a starfield.
- **Organized zones** (solid borders): reminders, health, time, routines — the boring,
  dopamine-draining stuff, handled.
- **Messy zones** (dashed borders): ideas, captures, someday — patterned chaos, like an
  AuDHD room.
- **YOU** sits at the center. Urgent things drift inward; cooling things drift out. The map
  breathes with priority.

**Capture → name → drop.** Type or speak a thought in under a second, before it vanishes.
On-device Apple Intelligence reads it, **names it by its main idea**, and files it into the
right cluster with a focus-dive zoom. The clean name shows on the node; your raw words stay as
a checkable sub-detail underneath.

**Dopamine, honestly.** Every action has a haptic + a reveal. Rewards never repeat twice in a
row (a variety engine fights habituation). Real milestones — things you actually *cleared* —
trigger a collection reveal with a laser/flame show from the YOU stage. The reward is the
*insight*, never a fake point.

---

## Design constraints (non-negotiable)

Three risks shape every screen. They aren't features — they're the floor.

1. **PDA (demand avoidance).** The app pulls; it never pushes. Declarative over imperative
   ("the dishes exist," not "do the dishes"). It suggests, never commands. There's a no-demand
   posture throughout: it reflects and shows, and lets you reach for it.
2. **RSD (rejection sensitivity).** No red, no overdue counts, no "you missed." Incomplete
   things gently fade — they never accumulate guilt. Calendar clashes are amber *information*,
   not alarms. The emotional floor, at worst, is "you're fine."
3. **Novelty death.** The #1 reason these users abandon apps: novelty wears off in 2–3 weeks.
   So the app visibly evolves — hidden easter eggs, rotating rewards, surprise drops, a growing
   constellation. Irregular use is normal and celebrated, never treated as failure.

---

## The systems

| System | What it does | Key files |
|---|---|---|
| **Brain map** | Spatial cluster canvas, draggable + persisted, collision-avoided, with a starfield + holographic tilt | `BrainMapView`, `ClusterView`, `StarfieldView`, `TiltLayer` |
| **Capture funnel** | Sub-second capture → on-device AI names + classifies → focus-dive drop | `CaptureController`, `ClusterClassifier`, `QuickCaptureBar`, `DropBoxView` |
| **Voice capture** | Action Button → live speech-to-text → drop | `CaptureIntent`, `VoiceCapture`, `VoiceCaptureOverlay` |
| **Mood-adaptive UI** | Detects brain mode (overwhelm / low-battery / ready / hyperfocus) from *behaviour*, learns your personal baseline, and transforms the whole UI | `MoodDetector`, `UserBaseline`, `MoodTheme` |
| **Mood surfacing** | Three silent layers: an aurora sky-glow, an in-app badge, and mood-tinted alternate app icons. **Never names the state.** | `AuroraView`, `MoodBadge`, `AppIconManager` |
| **Time space** | Aggregates Apple / Google / Outlook calendars + Reminders, detects overlaps, and auto-reschedules into your next free slot — favoring your good-energy hours | `CalendarService`, `ClashPreference` |
| **Health** | Steps / sleep / heart-rate / energy as live nodes | `HealthService` |
| **Dopamine + collection** | Variety-rotating haptics, gyro-aware fling, milestone reveals, a progress ring around YOU | `HapticEngine`, `Progression`, `LaserShowView` |
| **Knowledge crumbs** | Tiny brain-science + personal-pattern drops, scattered on the map, found not pushed | `KnowledgeCrumb`, `PatternService`, `CrumbView` |
| **Paralysis support** | On return after a freeze: no "welcome back," no guilt — warm breadcrumbs (your own words, one easy win, a coaching note you left yourself), each with a "not yet" exit. Survival mode dims everything to one glowing thing | `ReturnState`, `BreadcrumbOverlay`, `SurvivalBanner`, `CoachingNote` |
| **Spatial audio + focus music** | Per-cluster 3D tones; a mood-reactive ambient pad that re-tunes its chord/tempo live | `SpatialAudioService` |
| **Motion** | Gyro-driven holographic depth + acceleration-aware gesture sensitivity, all isolated for 60–120 fps | `MotionAdaptor`, `MapParameters` |
| **First run** | A calm, skippable 3-breath intro; permissions deferred until after it | `OnboardingView`, `AppSettings` |

---

## Notable algorithms

The heavy lifting is done with deliberate, efficient algorithms rather than brute force:

- **Sweep-line clash detection** — calendar overlaps found in one sorted pass: O(n log n) sort
  + O(n) scan, never O(n²) pairwise.
- **Free-slot search** — auto-reschedule merges busy intervals, then linearly scans the gaps
  for the first opening that fits, in a two-pass preference (your good hours first, any waking
  hour second).
- **Wavetable synthesis** — spatial audio walks a precomputed sine table with an integer phase
  accumulator instead of calling `sin()` per sample (~150k transcendental calls/sec avoided).
- **EMA baselines** — mood detection learns *your* normal tap rhythm / completion rate /
  active hours via exponential moving averages, then judges deviation from your personal norm.
- **Learned clash priority** — when two events overlap, the app leans toward the one whose
  keywords you've historically protected, and reinforces that each time you choose.

---

## Gesture vocabulary

All in trackpad logic — precise hands, magical atmosphere:

| Gesture | Action |
|---|---|
| Tap a cluster | Open it (instant, with a tactile dip + pop) |
| Drag a cluster | Move it (threshold-gated so taps never jiggle) |
| One-finger drag (background) | Pan, with inertia + rubber-band at the edges |
| Pinch | Zoom (0.4×–2.5×) |
| Two-finger rotate | Spin the canvas — self-levels to upright |
| Double-tap | Reset pan / zoom / rotation |
| Four-finger tap | Constellation overview (the trackpad Launchpad gesture) |
| Tilt the phone | Holographic 3D float, relative to how you're holding it |

---

## The sensory dial

A single control (top-right) cycles three intensities, so the app meets each brain where it is:

- **Calm** — flattens the 3D, mutes audio, no chaos, no laser shows. For overwhelm.
- **Normal** — the balanced default.
- **Insane** — the rave never stops: a laser/flame show on *every* completion, max-intensity
  longer shows, bigger tilt, frequent surprise drops.

A separate toggle enables the mood-reactive focus music.

> 🥚 The YOU stage is secretly a DJ booth (long-press it). Some words typed into capture do
> things. Found, not announced — that's the point.

---

## Architecture

Clean layering, no third-party dependencies:

```
Models (SwiftData)   Item.swift (Cluster, BrainItem), CoachingNote
        ↑
Services             ClusterClassifier · Health · Calendar · Motion · Mood ·
(singletons,         Pattern · Progression · Haptic · SpatialAudio · Return ·
 @Observable)        ClashPreference · AppSettings
        ↑
Views                BrainMapView (composition root) ← ClusterView,
                     ClusterDetailView, overlays, CaptureController,
                     MapCanvasGestures, TiltLayer
```

`BrainMapView` is the composition root; the capture flow (`CaptureController`) and the canvas
gestures (`MapCanvasGestures`) are extracted into their own types, and the big body is split
into `@ViewBuilder` overlay properties. Performance is baked in: `@Observable` for granular
re-renders, threshold-gated motion, an isolated 60 Hz tilt layer, and all audio-engine work off
the main thread.

---

## Tech stack

- **SwiftUI** — the spatial map, animations, haptics, gestures
- **SwiftData** — local-first, offline, private; behavioural data never leaves the device
- **Apple Intelligence (FoundationModels)** — the on-device capture funnel (keyword fallback
  when unavailable)
- **EventKit · HealthKit · CoreMotion · CoreHaptics · AVAudioEngine · Speech · AppIntents**

---

## Build & run

1. Open `Unstuck.xcodeproj` in a recent Xcode (iOS 18+ / Apple-Intelligence era).
2. **Signing & Capabilities → Team** → select your account.
3. Run on a **real device** — most of the magic (haptics, gyro, spatial audio, on-device AI,
   real Health/Calendar data) needs hardware. The simulator shows mock data.

**Action Button:** Settings → Action Button → App Shortcut → Unstuck → "Capture a Thought"
turns the side button into instant voice capture.

---

## Privacy

Everything is on-device. Health, calendar, reminders, microphone, and speech are **read-only**
and never collected, transmitted, or linked. Your patterns, your baseline, your words — all
local. Your brain stays yours.

---

## Status & roadmap

**Alpha-prep complete.** All six build phases shipped; runs on-device. First-run onboarding,
deferred permissions, the calm/insane dial, mood detection, calendar/health integration, and
the full reward layer are in. Builds clean, unit tests pass.

**Deferred, by design:**
- **Dynamic Island Live Activity** — a focus-session pill (mood + music + timer); needs a
  Widget Extension target.
- **Companion** — a customizable VTuber-quality character (Live2D Cubism) idling in the corner
  as ambient body-double presence; needs an artist + rigger. Event hooks are already emitted.

**To ship the alpha:** a paid Apple Developer account, an App Store Connect record, privacy
nutrition labels (all "on-device, not collected"), and a tester note for Action Button setup.
