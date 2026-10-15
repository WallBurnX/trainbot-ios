import Foundation
import UIKit
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var lastSyncSummary: String = "Готово к синхронизации (HealthKit / Быстрые команды iOS)"
    @Published var isSyncing: Bool = false

    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Works with both Paid Apple Developer certificates (native HKHealthStore)
    /// and Free Apple ID Sideloadly/AltStore builds (falls back to iOS Shortcuts bridge if entitlement is absent).
    func requestAuthorizationAndSync() async {
        #if canImport(HealthKit)
        guard isAvailable else {
            lastSyncSummary = "HealthKit недоступен на этом устройстве"
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let store = HKHealthStore()
        var readTypes = Set<HKObjectType>()
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) { readTypes.insert(weight) }
        if let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { readTypes.insert(bodyFat) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { readTypes.insert(steps) }
        if let restingHR = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { readTypes.insert(restingHR) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { readTypes.insert(activeEnergy) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { readTypes.insert(hrv) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { readTypes.insert(sleep) }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            let payload = await collectTodayMetrics(store: store)
            try await TrainBotAPIClient.shared.syncHealthKit(payload: payload)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            lastSyncSummary = "Синхронизировано с Apple Health в \(formatter.string(from: Date()))"
        } catch {
            // If installed via free Apple ID (Sideloadly/AltStore) without paid HealthKit entitlement:
            copyShortcutConfigToClipboard()
            lastSyncSummary = "Бесплатный сертификат Apple ID не включает прямой HealthKit entitlement — скопирован URL и токен для «Быстрых команд» iOS!"
        }
        #else
        copyShortcutConfigToClipboard()
        #endif
    }

    func copyShortcutConfigToClipboard() {
        let base = TrainBotAPIClient.shared.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let tok = TrainBotAPIClient.shared.token ?? ""
        let info = """
        URL: \(base)/api/v2/healthkit/sync
        Authorization: Bearer \(tok)
        """
        UIPasteboard.general.string = info
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }

    #if canImport(HealthKit)
    private func collectTodayMetrics(store: HKHealthStore) async -> [String: Any] {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var payload: [String: Any] = ["date": dateFormatter.string(from: now)]

        if let steps = await fetchCumulativeSum(store: store, .stepCount, unit: .count(), start: startOfDay, end: now) {
            payload["steps"] = Int(steps.rounded())
        }
        if let activeKcal = await fetchCumulativeSum(store: store, .activeEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: now) {
            payload["active_calories"] = Int(activeKcal.rounded())
        }
        if let weight = await fetchLatestQuantity(store: store, .bodyMass, unit: .gramUnit(with: .kilo)) {
            payload["weight"] = (weight * 10).rounded() / 10.0
        }
        if let rhr = await fetchLatestQuantity(store: store, .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())) {
            payload["resting_pulse"] = Int(rhr.rounded())
        }
        if let hrv = await fetchLatestQuantity(store: store, .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) {
            payload["hrv_ms"] = Int(hrv.rounded())
        }
        if let sleepHours = await fetchLastNightSleepHours(store: store, now: now) {
            payload["sleep_hours"] = (sleepHours * 10).rounded() / 10.0
        }
        return payload
    }

    private func fetchCumulativeSum(
        store: HKHealthStore,
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(store: HKHealthStore, _ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchLastNightSleepHours(store: HKHealthStore, now: Date) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = now.addingTimeInterval(-24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                var asleepSeconds: TimeInterval = 0
                for s in categorySamples {
                    if s.value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
                       s.value != HKCategoryValueSleepAnalysis.awake.rawValue {
                        asleepSeconds += s.endDate.timeIntervalSince(s.startDate)
                    }
                }
                let hours = asleepSeconds / 3600.0
                continuation.resume(returning: hours > 0.5 ? hours : nil)
            }
            store.execute(query)
        }
    }
    #endif
}
