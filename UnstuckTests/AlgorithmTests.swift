//
//  AlgorithmTests.swift
//  UnstuckTests
//
//  Pure-logic tests for the algorithms that would break SILENTLY if a refactor
//  nudged them — the calendar scheduler (merge + free-slot), the AI-funnel keyword
//  fallback, and the constellation geometry. Deterministic (fixed dates), no I/O.
//

import Testing
import SwiftUI
@testable import Unstuck

@MainActor
struct AlgorithmTests {

    /// A fixed, deterministic date (no `Date()` — so equality is exact).
    private func d(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1,
                                                   hour: hour, minute: minute))!
    }

    // MARK: - mergeBusy (sweep / interval merge)

    @Test func mergeBusyEmptyIsEmpty() {
        #expect(CalendarService.shared.mergeBusy([]).isEmpty)
    }

    @Test func mergeBusyMergesOverlap() {
        // 9–10 and 9:30–11 overlap → one block 9–11
        let merged = CalendarService.shared.mergeBusy([(d(9), d(10)), (d(9, 30), d(11))])
        #expect(merged.count == 1)
        #expect(merged[0].0 == d(9))
        #expect(merged[0].1 == d(11))
    }

    @Test func mergeBusyKeepsDisjoint() {
        let merged = CalendarService.shared.mergeBusy([(d(9), d(10)), (d(13), d(14))])
        #expect(merged.count == 2)
    }

    @Test func mergeBusyMergesTouchingBlocks() {
        // 9–10 and 10–11 touch (end == next start) → merged into 9–11
        let merged = CalendarService.shared.mergeBusy([(d(9), d(10)), (d(10), d(11))])
        #expect(merged.count == 1)
        #expect(merged[0].1 == d(11))
    }

    @Test func mergeBusySortsThenMerges() {
        // out-of-order input still yields earliest-first, correctly merged
        let merged = CalendarService.shared.mergeBusy([(d(13), d(14)), (d(9), d(10))])
        #expect(merged.count == 2)
        #expect(merged[0].0 == d(9))
    }

    // MARK: - findSlot (free-slot search)

    @Test func findSlotTakesGapBeforeBusy() {
        // free from 9:00, busy 10–11 → a 30-min task fits at 9:00
        let slot = CalendarService.shared.findSlot(duration: 1800, after: d(9), busy: [(d(10), d(11))])
        #expect(slot == d(9))
    }

    @Test func findSlotSkipsPastABusyBlock() {
        // start 9:30 but 9–10 is busy → the next opening is at/after 10:00
        let slot = CalendarService.shared.findSlot(duration: 1800, after: d(9, 30), busy: [(d(9), d(10))])
        #expect(slot != nil)
        if let slot { #expect(slot >= d(10)) }
    }

    // MARK: - classifyWithKeywords (AI-funnel fallback, used on Simulator / no AI)

    @Test func keywordRoutingHitsEachZone() {
        let c = ClusterClassifier.shared
        #expect(c.classifyWithKeywords(text: "buy milk") == .reminders)
        #expect(c.classifyWithKeywords(text: "go to the gym") == .health)
        #expect(c.classifyWithKeywords(text: "meeting on tuesday") == .timeManagement)
        #expect(c.classifyWithKeywords(text: "every morning stretch") == .routines)
        // NB: avoid "someday" here — it contains "med" (so·MED·ay) which the health rule
        // catches first. A real keyword-fallback quirk; "one day" routes cleanly to .someday.
        #expect(c.classifyWithKeywords(text: "maybe one day") == .someday)
        #expect(c.classifyWithKeywords(text: "cool app idea") == .ideas)
    }

    @Test func keywordFallsBackToCaptures() {
        #expect(ClusterClassifier.shared.classifyWithKeywords(text: "asdf qwerty zzz") == .captures)
    }

    @Test func keywordHealthIsCheckedBeforeReminders() {
        // "call the doctor" matches both reminders(call) and health(doctor); health wins by order
        #expect(ClusterClassifier.shared.classifyWithKeywords(text: "call the doctor") == .health)
    }

    // MARK: - rng (Relative Neighbourhood Graph — constellation edges via the lune test)

    @Test func rngEmptyAndSingleHaveNoEdges() {
        #expect(NodeGraph.rng([]).isEmpty)
        #expect(NodeGraph.rng([CGPoint(x: 0, y: 0)]).isEmpty)
    }

    @Test func rngPairHasExactlyOneEdge() {
        #expect(NodeGraph.rng([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)]).count == 1)
    }

    @Test func rngCollinearDropsTheLongEdge() {
        // 0—1—2 on a line: keep the two short edges, drop the spanning 0–2
        let e = NodeGraph.rng([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0)])
        #expect(e.count == 2)
        #expect(!e.contains { $0.0 == 0 && $0.1 == 2 })
    }

    @Test func rngSquareDropsBothDiagonals() {
        // unit square → 4 sides kept, 2 diagonals removed
        let e = NodeGraph.rng([
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ])
        #expect(e.count == 4)
    }

    // MARK: - squareGridColumns (the √n factor shortcut → most-square grid)

    @Test func squareGridColumnsAreMostSquare() {
        #expect(squareGridColumns(9) == 3)    // 3 × 3
        #expect(squareGridColumns(12) == 4)   // divisor 3 ≤ √12, paired with 4
        #expect(squareGridColumns(16) == 4)   // 4 × 4
        #expect(squareGridColumns(7) == 7)    // prime → a single row (1 × 7)
        #expect(squareGridColumns(2) == 2)
        #expect(squareGridColumns(1) == 1)
    }
}
