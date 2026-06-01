//
//  UnstuckTests.swift
//  UnstuckTests
//

import Testing
@testable import Unstuck

@MainActor
struct UnstuckTests {

    // MARK: - UserBaseline (the personal mood-learning core)

    @Test func baselineLearnsTapRhythm() {
        var b = UserBaseline()
        let startMean = b.tapGapMean
        b.observeTapGap(10)               // a slow gap
        // EMA should nudge the mean upward, but not jump all the way
        #expect(b.tapGapMean > startMean)
        #expect(b.tapGapMean < 10)
        #expect(b.sampleCount == 1)
    }

    @Test func baselineWarmsUpAfter25Samples() {
        var b = UserBaseline()
        #expect(b.isWarmedUp == false)
        for _ in 0..<25 { b.observeTapGap(4) }
        #expect(b.isWarmedUp == true)
    }

    @Test func tapGapZIsSignedByDeviation() {
        let b = UserBaseline()            // default mean 4, std 2
        #expect(b.tapGapZ(2) < 0)         // faster than usual → negative
        #expect(b.tapGapZ(8) > 0)         // slower than usual → positive
    }

    @Test func hourIsLowNeedsEnoughHistory() {
        var b = UserBaseline()
        #expect(b.hourIsLow(3) == false)  // no data yet → never flags
        // Build a clear pattern: very active at hour 9, never at hour 3
        for _ in 0..<60 { b.observeHour(9) }
        #expect(b.hourIsLow(9) == false)  // the busy hour is not low
        #expect(b.hourIsLow(3) == true)   // the unvisited hour is low
    }

    // MARK: - ClashPreference (learned event priority)

    @Test func clashPreferenceLeansTowardKept() {
        let p = ClashPreference.shared
        let base = p.score("Dentist appointment")
        p.reinforce(kept: "Dentist appointment", over: "Random chore")
        #expect(p.score("Dentist appointment") > base)
    }
}
