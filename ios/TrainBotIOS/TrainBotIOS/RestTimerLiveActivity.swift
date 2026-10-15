import Foundation
import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit

struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date
        var exerciseName: String
        var nextTargetText: String
    }
    var machineId: String
}
#endif

@MainActor
final class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()

    @Published var isRunning: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 120
    @Published var exerciseName: String = ""
    @Published var nextTargetText: String = ""

    private var endDate: Date?
    private var timerCancellable: AnyCancellable?

    func startRestTimer(seconds: Int, exerciseName: String, nextTargetText: String) {
        self.totalSeconds = max(15, seconds)
        self.remainingSeconds = self.totalSeconds
        self.exerciseName = exerciseName
        self.nextTargetText = nextTargetText
        let end = Date().addingTimeInterval(TimeInterval(self.totalSeconds))
        self.endDate = end
        self.isRunning = true

        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }

        startLiveActivity(endDate: end, exerciseName: exerciseName, nextTargetText: nextTargetText)
    }

    func addSeconds(_ delta: Int) {
        guard isRunning, let currentEnd = endDate else { return }
        let newEnd = currentEnd.addingTimeInterval(TimeInterval(delta))
        self.endDate = newEnd
        self.totalSeconds = max(self.totalSeconds + delta, 15)
        tick()
    }

    func stop() {
        isRunning = false
        remainingSeconds = 0
        timerCancellable?.cancel()
        endLiveActivities()
    }

    private func tick() {
        guard let endDate = endDate else {
            stop()
            return
        }
        let left = Int(ceil(endDate.timeIntervalSinceNow))
        if left <= 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            stop()
        } else {
            remainingSeconds = left
        }
    }

    var formattedRemaining: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    private func startLiveActivity(endDate: Date, exerciseName: String, nextTargetText: String) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            endLiveActivities()
            let attributes = RestTimerAttributes(machineId: exerciseName)
            let state = RestTimerAttributes.ContentState(
                endDate: endDate,
                exerciseName: exerciseName,
                nextTargetText: nextTargetText
            )
            _ = try? Activity<RestTimerAttributes>.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endDate.addingTimeInterval(30)),
                pushType: nil
            )
        }
        #endif
    }

    private func endLiveActivities() {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                for activity in Activity<RestTimerAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }
}
