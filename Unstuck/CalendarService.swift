import Foundation
import SwiftUI
import EventKit

/// A surfaced overlap with a gentle, pattern-based lean (never a command).
struct ClashSuggestion: Identifiable {
    let id = UUID()
    let time: String
    let keep: String      // the event the user's patterns lean toward protecting
    let drop: String      // the other one
    let reason: String
}

/// Pulls upcoming events + reminders from EVERY source on the device — Apple, Google,
/// Outlook, iCloud, Reminders — through EventKit. Detects overlaps with a sweep-line,
/// and AUTO-RESCHEDULES the dropped event into the next free slot (favoring your good
/// hours) using a merge-and-scan free-slot search. All O(n log n) — the efficient path.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private var cached: [HealthSnapshot]?
    private init() { moved = Self.loadMoved() }

    private(set) var clashes: [ClashSuggestion] = []
    private var lastEvents: [Ev] = []
    private var moved: [String: Date]            // title → rescheduled start (persisted)

    private let teal  = Color(red: 0.3, green: 0.85, blue: 0.75)
    private let amber = Color(red: 1.0, green: 0.62, blue: 0.25)
    private let green = Color(red: 0.45, green: 0.9, blue: 0.55)   // moved / resolved

    private struct Ev {
        let title: String; var start: Date; var end: Date
        var urgency: Double; var clashes: Bool; var moved: Bool
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    // MARK: - Public

    func fetchUpcoming(forceRefresh: Bool = false) async -> [HealthSnapshot] {
        // Never request calendar/reminders access before the user has been introduced
        guard AppSettings.shared.hasOnboarded else { return [] }
        if !forceRefresh, let cached { return cached }

        var events = await loadEvents()
        // Apply any rescheduled times the user has accepted
        events = events.map { e in
            guard let newStart = moved[e.title] else { return e }
            var m = e; m.start = newStart; m.end = newStart + e.duration; m.moved = true; return m
        }
        events = detectClashes(events)     // sweep-line; moved events no longer clash
        lastEvents = events

        var nodes: [HealthSnapshot] = events.map { e in
            if e.moved {
                return HealthSnapshot(label: "\(short(e.title)) → \(timeString(e.start))",
                                      icon: "arrow.turn.up.right", urgency: 0.5, tint: green)
            }
            return HealthSnapshot(
                label: "\(timeString(e.start)) \(short(e.title))",
                icon: e.clashes ? "exclamationmark.2" : "calendar",
                urgency: e.clashes ? 0.9 : clamp(e.urgency),
                tint: e.clashes ? amber : teal)
        }
        for r in await loadReminders() {
            nodes.append(HealthSnapshot(label: "\(timeString(r)) ·", icon: "bell.fill", urgency: 0.4, tint: teal))
        }

        let final = Array(nodes.prefix(8))
        cached = final
        return final
    }

    /// User chose which to protect → learn it, AND auto-reschedule the dropped one.
    func resolve(keep: String, drop: String) {
        ClashPreference.shared.reinforce(kept: keep, over: drop)

        if let dropEv = lastEvents.first(where: { $0.title == drop }) {
            let busy = lastEvents.filter { $0.title != drop }.map { ($0.start, $0.end) }
            let earliest = max(Date(), dropEv.start)
            if let slot = findSlot(duration: dropEv.duration, after: earliest, busy: busy) {
                moved[drop] = slot
                saveMoved()
            }
        }
        cached = nil   // recompute with the new placement
    }

    // MARK: - Sweep-line clash detection (O(n log n) + O(n))

    private func detectClashes(_ input: [Ev]) -> [Ev] {
        guard input.count > 1 else { clashes = []; return input }
        var ev = input.sorted { $0.start < $1.start }
        var maxEnd = Date.distantPast
        var maxIdx = -1
        var pairs: [(Int, Int)] = []
        for i in ev.indices {
            if ev[i].start < maxEnd && !ev[i].moved {
                ev[i].clashes = true
                if maxIdx >= 0 && !ev[maxIdx].moved { ev[maxIdx].clashes = true; pairs.append((maxIdx, i)) }
            }
            if ev[i].end > maxEnd { maxEnd = ev[i].end; maxIdx = i }
        }
        clashes = pairs.map { suggestion(ev[$0.0], ev[$0.1]) }
        return ev
    }

    // MARK: - Free-slot search (merge busy intervals, scan gaps)

    /// First gap ≥ duration at/after `after`, within waking hours, preferring the
    /// user's non-low-energy hours. Merge is O(n log n); the scan is O(n).
    private func findSlot(duration: TimeInterval, after: Date, busy: [(Date, Date)]) -> Date? {
        let merged = mergeBusy(busy)
        let baseline = UserBaseline.load()
        var cursor = after

        func acceptable(_ t: Date) -> Bool {
            let h = Calendar.current.component(.hour, from: t)
            return h >= 7 && h <= 22                       // waking window
        }
        func preferred(_ t: Date) -> Bool {
            !baseline.hourIsLow(Calendar.current.component(.hour, from: t))
        }
        // Two passes: first insist on a preferred (good-energy) slot, then any waking slot.
        for requirePreferred in [true, false] {
            cursor = after
            for iv in merged {
                if iv.0 > cursor {                         // a gap before this busy block
                    let gap = iv.0.timeIntervalSince(cursor)
                    if gap >= duration, acceptable(cursor), (!requirePreferred || preferred(cursor)) {
                        return cursor
                    }
                }
                cursor = max(cursor, iv.1)
            }
            // Open-ended gap after the last busy block
            if acceptable(cursor), (!requirePreferred || preferred(cursor)) { return cursor }
        }
        return cursor
    }

    private func mergeBusy(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        guard !intervals.isEmpty else { return [] }
        let s = intervals.sorted { $0.0 < $1.0 }
        var merged = [s[0]]
        for iv in s.dropFirst() {
            if iv.0 <= merged[merged.count - 1].1 {
                merged[merged.count - 1].1 = max(merged[merged.count - 1].1, iv.1)
            } else {
                merged.append(iv)
            }
        }
        return merged
    }

    // MARK: - Priority lean (user patterns)

    private func priorityScore(_ e: Ev) -> Double {
        let hour = Calendar.current.component(.hour, from: e.start)
        var s = ClashPreference.shared.score(e.title)
        if UserBaseline.load().hourIsLow(hour) { s -= 0.3 }
        s += e.urgency * 0.15
        return s
    }

    private func suggestion(_ a: Ev, _ b: Ev) -> ClashSuggestion {
        let keep = priorityScore(a) >= priorityScore(b) ? a : b
        let drop = priorityScore(a) >= priorityScore(b) ? b : a
        let reason: String
        if ClashPreference.shared.score(keep.title) > 0.05 {
            reason = "you usually protect things like this"
        } else if UserBaseline.load().hourIsLow(Calendar.current.component(.hour, from: drop.start)) {
            reason = "you're usually low-energy around then"
        } else if keep.start <= drop.start {
            reason = "this one comes first"
        } else {
            reason = "leaning here for now"
        }
        return ClashSuggestion(time: timeString(keep.start), keep: keep.title, drop: drop.title, reason: reason)
    }

    // MARK: - EventKit (all configured accounts) + mock

    private func loadEvents() async -> [Ev] {
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToEvents { ok, _ in c.resume(returning: ok) }
        }
        let now = Date()
        guard granted else { return mockEvents(now) }

        let end = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let span = max(1, end.timeIntervalSince(now))
        let real = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { e in
                Ev(title: e.title ?? "event", start: e.startDate, end: e.endDate,
                   urgency: 1.0 - (e.startDate.timeIntervalSince(now) / span),
                   clashes: false, moved: false)
            }
        return real.isEmpty ? mockEvents(now) : real
    }

    private func loadReminders() async -> [Date] {
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToReminders { ok, _ in c.resume(returning: ok) }
        }
        guard granted else { return [] }
        let reminders: [EKReminder] = await withCheckedContinuation { c in
            store.fetchReminders(matching: store.predicateForReminders(in: nil)) { c.resume(returning: $0 ?? []) }
        }
        return reminders.filter { !$0.isCompleted }
            .compactMap { $0.dueDateComponents?.date }
            .filter { $0 > Date() }.sorted()
    }

    // Mock with a deliberate clash so the feature is visible without real accounts
    private func mockEvents(_ now: Date) -> [Ev] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        }
        return [
            Ev(title: "Standup",  start: at(9),  end: at(9, 30),  urgency: 0.8, clashes: false, moved: false),
            Ev(title: "Dentist",  start: at(14), end: at(15),     urgency: 0.9, clashes: false, moved: false),
            Ev(title: "Call Mom", start: at(14), end: at(14, 30), urgency: 0.7, clashes: false, moved: false),
            Ev(title: "Gym",      start: at(18), end: at(19),     urgency: 0.4, clashes: false, moved: false),
        ]
    }

    // MARK: - Persistence + helpers

    private static let movedKey = "unstuck.movedEvents"
    private static func loadMoved() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: movedKey),
              let d = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        // Drop stale reschedules whose time has already passed — no accumulation
        let cutoff = Date().addingTimeInterval(-3600)
        return d.filter { $0.value > cutoff }
    }
    private func saveMoved() {
        if let data = try? JSONEncoder().encode(moved) {
            UserDefaults.standard.set(data, forKey: Self.movedKey)
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "ha"
        return f.string(from: d).lowercased()
    }
    private func short(_ s: String) -> String { s.count <= 14 ? s : String(s.prefix(13)) + "…" }
    private func clamp(_ x: Double) -> Double { Swift.min(1, Swift.max(0, x)) }
}
