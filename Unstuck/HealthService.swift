import Foundation
import SwiftUI
import HealthKit

/// A live read-only "data node" shown inside a cluster (health metrics, calendar
/// events, reminders…). `tint` overrides the default teal — e.g. amber for a clash.
struct HealthSnapshot {
    let label: String       // e.g. "8,432 steps" / "2pm Standup"
    let icon: String        // SF Symbol name
    let urgency: Double     // 0–1 for map gravity
    var tint: Color? = nil  // nil = default teal
}

@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()
    private var cachedSnapshot: [HealthSnapshot]? = nil

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Request permission + fetch

    func fetchSnapshot(forceRefresh: Bool = false) async -> [HealthSnapshot] {
        // Never request Health access before the user has been introduced
        guard AppSettings.shared.hasOnboarded else { return [] }
        if !forceRefresh, let cached = cachedSnapshot { return cached }
        guard isAvailable else {
            let mock = mockSnapshot()
            cachedSnapshot = mock
            return mock
        }

        let typeIdentifiers: [HKObjectType?] = [
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ]
        let types = Set(typeIdentifiers.compactMap { $0 })

        do {
            try await store.requestAuthorization(toShare: [], read: types)
        } catch {
            return mockSnapshot()
        }

        async let steps   = fetchSteps()
        async let heart   = fetchHeartRate()
        async let energy  = fetchActiveEnergy()
        async let sleep   = fetchSleep()

        var results: [HealthSnapshot] = []
        if let s  = await steps  { results.append(s)  }
        if let h  = await heart  { results.append(h)  }
        if let e  = await energy { results.append(e)  }
        if let sl = await sleep  { results.append(sl) }

        let final = results.isEmpty ? mockSnapshot() : results
        cachedSnapshot = final
        return final
    }

    // MARK: - Mock data for Simulator / demo

    private func mockSnapshot() -> [HealthSnapshot] {
        let steps  = Int.random(in: 3_000...12_000)
        let bpm    = Int.random(in: 58...95)
        let kcal   = Int.random(in: 150...700)
        let sleepH = Int.random(in: 5...9)
        let sleepM = Int.random(in: 0...59)

        let stepsFormatted = NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal)
        let sleepLabel = sleepM > 0 ? "\(sleepH)h \(sleepM)m sleep" : "\(sleepH)h sleep"

        return [
            HealthSnapshot(label: "\(stepsFormatted) steps", icon: "figure.walk",
                           urgency: min(1.0, Double(steps) / 10_000)),
            HealthSnapshot(label: "\(bpm) bpm",              icon: "heart.fill",
                           urgency: min(1.0, max(0, Double(bpm - 50) / 80))),
            HealthSnapshot(label: "\(kcal) kcal",            icon: "flame.fill",
                           urgency: min(1.0, Double(kcal) / 600)),
            HealthSnapshot(label: sleepLabel,                icon: "moon.fill",
                           urgency: max(0, min(1.0, Double(8 - sleepH) / 3))),
        ]
    }

    // MARK: - Individual fetches

    private func fetchSteps() async -> HealthSnapshot? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let value = await sumToday(type: type, unit: .count())
        guard value > 0 else { return nil }
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: Int(value)), number: .decimal)
        // 10k steps = urgency 1.0, scale below that
        let urgency = min(1.0, value / 10_000)
        return HealthSnapshot(label: "\(formatted) steps", icon: "figure.walk", urgency: urgency)
    }

    private func fetchHeartRate() async -> HealthSnapshot? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        guard let value = await mostRecentSample(type: type, unit: HKUnit(from: "count/min")) else { return nil }
        let bpm = Int(value)
        // Resting ~60, elevated ~100+
        let urgency = min(1.0, max(0, (value - 50) / 80))
        return HealthSnapshot(label: "\(bpm) bpm", icon: "heart.fill", urgency: urgency)
    }

    private func fetchActiveEnergy() async -> HealthSnapshot? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let value = await sumToday(type: type, unit: .kilocalorie())
        guard value > 0 else { return nil }
        let urgency = min(1.0, value / 600) // 600 kcal goal
        return HealthSnapshot(label: "\(Int(value)) kcal", icon: "flame.fill", urgency: urgency)
    }

    private func fetchSleep() async -> HealthSnapshot? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now = Date()
        guard let yesterday = Calendar.current.date(byAdding: .hour, value: -18, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let total = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                guard total > 0 else { cont.resume(returning: nil); return }
                let hours = total / 3600
                let h = Int(hours)
                let m = Int((hours - Double(h)) * 60)
                // 8h = urgency 0 (good), <5h = urgency 1.0 (needs attention)
                let urgency = max(0, min(1.0, (8 - hours) / 3))
                let label = m > 0 ? "\(h)h \(m)m sleep" : "\(h)h sleep"
                cont.resume(returning: HealthSnapshot(label: label, icon: "moon.fill", urgency: urgency))
            }
            self.store.execute(query)
        }
    }

    // MARK: - Helpers

    private func sumToday(type: HKQuantityType, unit: HKUnit) async -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func mostRecentSample(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                cont.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
