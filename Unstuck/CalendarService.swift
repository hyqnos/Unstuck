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
    private init() {
        moved = Self.loadDict(Self.movedKey); applied = Self.loadDict(Self.appliedKey)
        // Live sync: when the user edits a calendar or reminder ANYWHERE else (Google,
        // Apple, Outlook, Reminders), EventKit posts this — drop the cache and tell the
        // map to refresh, so external changes appear without reopening the app.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.externalChange() }
        }
    }

    private func externalChange() {
        cached = nil
        NotificationCenter.default.post(name: .calendarDataChanged, object: nil)
    }

    private(set) var clashes: [ClashSuggestion] = []
    private var lastEvents: [Ev] = []
    private var moved: [String: Date]            // title → start, VISUAL overlay (read-only calendars)
    private var applied: [String: Date]          // eventID → original start, written to the REAL calendar (undo)

    private let teal  = Color(red: 0.3, green: 0.85, blue: 0.75)
    private let amber = Color(red: 1.0, green: 0.62, blue: 0.25)
    private let green = Color(red: 0.45, green: 0.9, blue: 0.55)   // moved / resolved

    private struct Ev {
        let id: String                           // EKEvent.eventIdentifier / reminder id (synthetic for mocks)
        let title: String; var start: Date; var end: Date
        var urgency: Double; var clashes: Bool; var moved: Bool
        var writable: Bool                       // calendar.allowsContentModifications
        var isReminder: Bool = false             // reminders share the flow; written via EKReminder
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    // MARK: - Public

    func fetchUpcoming(forceRefresh: Bool = false) async -> [HealthSnapshot] {
        // Never request calendar/reminders access before the user has been introduced
        guard AppSettings.shared.hasOnboarded else { return [] }
        if !forceRefresh, let cached { return cached }

        var events = await loadEvents()
        events.append(contentsOf: await loadReminders())   // unify planners: reminders join the same clash flow
        // Reflect any moves: a visual overlay (read-only calendars) OR a real move
        // already written to the calendar (EventKit returns the new time itself).
        events = events.map { e in
            if let newStart = moved[e.title] {
                var m = e; m.start = newStart; m.end = newStart + e.duration; m.moved = true; return m
            }
            if applied[e.id] != nil { var m = e; m.moved = true; return m }
            return e
        }
        events = detectClashes(events)     // sweep-line; moved events no longer clash
        lastEvents = events

        let nodes: [HealthSnapshot] = events
            .sorted { $0.start < $1.start }
            .prefix(8)
            .map { e in
                if e.moved {
                    return HealthSnapshot(label: "\(short(e.title)) → \(timeString(e.start))",
                                          icon: "arrow.turn.up.right", urgency: 0.5, tint: green)
                }
                let baseIcon = e.isReminder ? "bell.fill" : "calendar"
                return HealthSnapshot(
                    label: "\(timeString(e.start)) \(short(e.title))",
                    icon: e.clashes ? "exclamationmark.2" : baseIcon,
                    urgency: e.clashes ? 0.9 : clamp(e.urgency),
                    tint: e.clashes ? amber : teal)
            }

        let final = Array(nodes)
        cached = final
        return final
    }

    /// User chose which to protect → learn it, then MOVE the dropped event.
    /// If its calendar is writable, the new time is written back through EventKit
    /// (one call → propagates to Apple/Google/Outlook). Otherwise we keep a
    /// visual overlay. Pattern logic (findSlot) still picks the slot.
    func resolve(keep: String, drop: String) {
        ClashPreference.shared.reinforce(kept: keep, over: drop)

        guard let dropEv = lastEvents.first(where: { $0.title == drop }) else { return }
        let busy = lastEvents.filter { $0.title != drop }.map { ($0.start, $0.end) }
        let earliest = max(Date(), dropEv.start)
        guard let slot = findSlot(duration: dropEv.duration, after: earliest, busy: busy) else {
            cached = nil; return
        }

        if dropEv.writable, applyMove(eventID: dropEv.id, isReminder: dropEv.isReminder, to: slot, duration: dropEv.duration) {
            applied[dropEv.id] = dropEv.start          // remember original, for undo
            saveDict(applied, Self.appliedKey)
        } else {
            moved[drop] = slot                          // visual overlay (read-only calendar)
            saveDict(moved, Self.movedKey)
        }
        cached = nil   // recompute with the new placement
    }

    /// Put a moved event back where it was — pull-to-undo, never framed as failure.
    func undo(_ title: String) {
        guard let ev = lastEvents.first(where: { $0.title == title }) else { return }
        if let original = applied[ev.id] {
            _ = applyMove(eventID: ev.id, isReminder: ev.isReminder, to: original, duration: ev.duration)
            applied[ev.id] = nil; saveDict(applied, Self.appliedKey)
        }
        if moved[title] != nil { moved[title] = nil; saveDict(moved, Self.movedKey) }
        cached = nil
    }

    /// Whether `title` currently shows as moved (so the UI can offer Undo).
    func isMoved(_ title: String) -> Bool {
        guard let ev = lastEvents.first(where: { $0.title == title }) else { return false }
        return moved[title] != nil || applied[ev.id] != nil
    }

    /// One cross-platform write. EventKit is the single backend for Apple, Google,
    /// and Outlook, so this save propagates the move to all of them. Returns false
    /// if the event is gone or the calendar is read-only (caller falls back to a
    /// visual overlay) — never throws upward.
    private func applyMove(eventID: String, isReminder: Bool, to newStart: Date, duration: TimeInterval) -> Bool {
        if isReminder {
            guard let reminder = store.calendarItem(withIdentifier: eventID) as? EKReminder,
                  reminder.calendar?.allowsContentModifications ?? false else { return false }
            // Same cross-platform path: EventKit writes the reminder back to its source.
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: newStart)
            do { try store.save(reminder, commit: true); return true }
            catch { return false }
        }
        guard let event = store.event(withIdentifier: eventID) else { return false }
        guard event.calendar?.allowsContentModifications ?? false else { return false }
        // Safety: never silently rewrite a recurring event — moving one occurrence can
        // split or corrupt the whole series. Leave those to a visual overlay only.
        guard !event.hasRecurrenceRules else { return false }
        event.startDate = newStart
        event.endDate = newStart.addingTimeInterval(duration)
        do { try store.save(event, span: .thisEvent, commit: true); return true }
        catch { return false }
    }

    // MARK: - Sweep-line clash detection (O(n log n) + O(n))

    private func detectClashes(_ input: [Ev]) -> [Ev] {
        guard input.count > 1 else { clashes = []; return input }
        // At equal starts, longer interval first so a zero-length reminder inside it is caught.
        var ev = input.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
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

        let end = Calendar.current.date(byAdding: .day, value: AppSettings.shared.calendarDays, to: now) ?? now
        let span = max(1, end.timeIntervalSince(now))
        let eventStore = self.store
        
        let real: [Ev] = await Task.detached {
            let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
            return eventStore.events(matching: predicate)
                .filter { !$0.isAllDay }
                .map { e in
                    Ev(id: e.eventIdentifier ?? UUID().uuidString,
                       title: e.title ?? "event", start: e.startDate, end: e.endDate,
                       urgency: 1.0 - (e.startDate.timeIntervalSince(now) / span),
                       clashes: false, moved: false,
                       writable: e.calendar?.allowsContentModifications ?? false)
                }
        }.value
        
        return real.isEmpty ? mockEvents(now) : real
    }

    private func loadReminders() async -> [Ev] {
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToReminders { ok, _ in c.resume(returning: ok) }
        }
        guard granted else { return [] }
        let reminders: [EKReminder] = await withCheckedContinuation { c in
            store.fetchReminders(matching: store.predicateForReminders(in: nil)) { c.resume(returning: $0 ?? []) }
        }
        let now = Date()
        return reminders
            .filter { !$0.isCompleted }
            .compactMap { r -> Ev? in
                guard let due = r.dueDateComponents?.date, due > now else { return nil }
                return Ev(id: r.calendarItemIdentifier, title: r.title ?? "reminder",
                          start: due, end: due, urgency: 0.4, clashes: false, moved: false,
                          writable: r.calendar?.allowsContentModifications ?? false, isReminder: true)
            }
            .sorted { $0.start < $1.start }
    }

    // Mock with a deliberate clash so the feature is visible without real accounts
    private func mockEvents(_ now: Date) -> [Ev] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        }
        return [
            Ev(id: "mock-standup", title: "Standup",  start: at(9),  end: at(9, 30),  urgency: 0.8, clashes: false, moved: false, writable: false),
            Ev(id: "mock-dentist", title: "Dentist",  start: at(14), end: at(15),     urgency: 0.9, clashes: false, moved: false, writable: false),
            Ev(id: "mock-callmom", title: "Call Mom", start: at(14), end: at(14, 30), urgency: 0.7, clashes: false, moved: false, writable: false),
            Ev(id: "mock-gym",     title: "Gym",      start: at(18), end: at(19),     urgency: 0.4, clashes: false, moved: false, writable: false),
        ]
    }

    // MARK: - Persistence + helpers

    private static let movedKey   = "unstuck.movedEvents"
    private static let appliedKey = "unstuck.appliedMoves"
    private static func loadDict(_ key: String) -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let d = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        // Drop stale entries whose time has already passed — no accumulation
        let cutoff = Date().addingTimeInterval(-3600)
        return d.filter { $0.value > cutoff }
    }
    private func saveDict(_ dict: [String: Date], _ key: String) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "ha"
        return f.string(from: d).lowercased()
    }
    private func short(_ s: String) -> String { s.count <= 14 ? s : String(s.prefix(13)) + "…" }
    private func clamp(_ x: Double) -> Double { Swift.min(1, Swift.max(0, x)) }
}

extension Notification.Name {
    /// Posted when EventKit reports an external change (an edit in Google / Apple /
    /// Outlook / Reminders) so the map can live-refresh.
    static let calendarDataChanged = Notification.Name("unstuck.calendarDataChanged")
}
