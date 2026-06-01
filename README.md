# Unstuck

A no-label brain tool for iOS. It helps you capture thoughts, manage time, break things
down, and get moving when you're stuck — by giving your mind a place to live *outside*
your head: a spatial map you can see, fill, and breathe with.

Unstuck isn't a productivity app (those carry shame baggage). It's a **thinking space** —
a "brain" you externalize into. It never tells you what to do. It shows you your own
patterns, your own data, and your own words from a good day, and lets the "oh" land on
its own.

---

## The idea

Your thoughts don't live in a list — they live in a *space*. Unstuck mirrors that:

- **The brain map** — a spatial canvas of clusters (reminders, health, time, routines,
  ideas, captures, someday). Organized zones have solid borders; messy zones, dashed.
  It breathes, drifts, and reorganizes as priorities shift.
- **Capture → name → drop** — type or speak a thought in under a second. On-device
  Apple Intelligence names it by its main idea and files it into the right cluster with
  a focus-dive animation. The raw input stays as a checkable sub-detail.
- **Dopamine, honestly** — every action has haptics + a reveal, rewards never repeat
  twice in a row, and milestones (real ones — things you actually cleared) trigger a
  collection reveal. The reward is the *insight*, never a fake point.

## What's inside

| System | What it does |
|---|---|
| **Mood-adaptive UI** | Detects your brain mode (overwhelm / low-battery / ready / hyperfocus) from behaviour — never a quiz — and learns *your* personal baseline over time. Surfaces it three ways: an aurora sky-glow, a silent in-app badge, and mood-tinted alternate app icons. Never names the state. |
| **Time space** | Aggregates Apple / Google / Outlook calendars + Reminders via EventKit. Sweep-line clash detection, pattern-based priority, and auto-reschedule into the next free slot. |
| **Health** | Steps / sleep / heart-rate / energy as live nodes (HealthKit). |
| **Paralysis support** | On return after a freeze: no "welcome back," no guilt — warm breadcrumbs (your own words, one easy win, a coaching note you left yourself), each with a "not yet" exit. Survival mode dims everything to one glowing thing. |
| **Sensory dial** | Calm ↔ Normal ↔ Insane. Calm flattens the 3D, mutes audio, no shows. Insane is a rave on every win. |
| **Spatial audio + focus music** | Per-cluster 3D tones and a mood-reactive ambient pad, tuned live to your detected mode. |
| **Motion** | Gyro-driven holographic tilt + acceleration-aware gesture sensitivity, all isolated for 60–120 fps. |

## Design constraints (non-negotiable)

These run through every screen:

1. **PDA (demand avoidance)** — the app pulls, never pushes. Declarative, not imperative.
   Suggestions, never commands.
2. **RSD (rejection sensitivity)** — no red, no overdue counts, no "you missed." Incomplete
   things gently fade; they never accumulate guilt. The emotional floor is "you're fine."
3. **Novelty death** — it visibly evolves. Hidden easter eggs, rotating rewards, surprises.
   Irregular use is normal and celebrated, never treated as failure.

## Tech

- **SwiftUI** — spatial map, animations, haptics, gestures
- **SwiftData** — local-first, offline, private. Behavioural data never leaves the device.
- **Apple Intelligence (FoundationModels)** — the on-device capture funnel (keyword fallback)
- **EventKit · HealthKit · CoreMotion · AVAudioEngine · ActivityKit**

Minimum target: recent iOS. No third-party dependencies.

## Build

1. Open `Unstuck.xcodeproj` in a recent Xcode.
2. Set your signing team (Signing & Capabilities → Team).
3. Run on a device — most of the magic (haptics, gyro, spatial audio, on-device AI)
   needs real hardware; the simulator shows mock data.

> **Action Button:** Settings → Action Button → App Shortcut → Unstuck → "Capture a Thought"
> turns the side button into instant voice capture.

## Status

Alpha-prep complete. All six build phases shipped; runs on-device. First-run onboarding,
permission deferral, calm/insane dial, and the reward layer are in. The companion character
(Live2D) and the Dynamic Island Live Activity are designed but intentionally deferred.

## Privacy

Everything is on-device. Health, calendar, reminders, mic, and speech are read-only and
never collected, transmitted, or linked. Your brain stays yours.
