import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var bootstrap: BootstrapResponse?
    @Published var activeBrief: MachineResolveResponse?
    @Published var todayWorkouts: [WorkoutRecord] = []
    @Published var todayTonnage: Double = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTab: Int = 0

    let api = TrainBotAPIClient.shared
    let timerManager = RestTimerManager.shared
    let healthKit = HealthKitManager.shared

    func refreshBootstrap() async {
        guard api.isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let boot = try await api.fetchBootstrap()
            self.bootstrap = boot
            self.activeBrief = boot.activeMachineBrief
            self.todayWorkouts = boot.todayWorkouts
            self.todayTonnage = boot.todayTonnage
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func activateMachine(equipmentId: String? = nil, qrPayload: String? = nil, query: String? = nil, imageData: Data? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resolved = try await api.resolveEquipment(
                qrPayload: qrPayload,
                query: query,
                equipmentId: equipmentId,
                imageJPEGData: imageData,
                activate: true
            )
            if resolved.status == "resolved" {
                self.activeBrief = resolved
                self.selectedTab = 0
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                self.errorMessage = "Тренажёр не распознан. Выбери его из каталога DDX для привязки QR."
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func logSet(weight: String, reps: String, sets: Int = 1, rir: String = "2") async {
        let eqId = activeBrief?.equipmentId ?? activeBrief?.equipment?.id
        let exName = activeBrief?.exerciseName ?? activeBrief?.equipment?.exerciseName
        do {
            let res = try await api.logQuickSet(
                equipmentId: eqId,
                exercise: exName,
                weight: weight,
                sets: sets,
                reps: reps,
                rir: rir
            )
            self.todayWorkouts = res.todayWorkouts
            self.todayTonnage = res.todayTonnage
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let restSec = activeBrief?.target?.restSeconds ?? 120
            timerManager.startRestTimer(
                seconds: restSec,
                exerciseName: exName ?? "Тренажёр",
                nextTargetText: activeBrief?.target?.loadText ?? "\(weight) кг × \(reps)"
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func undoSet(workoutId: Int) async {
        do {
            try await api.undoWorkout(id: workoutId)
            await refreshBootstrap()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

@main
struct TrainBotApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var apiClient = TrainBotAPIClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(apiClient)
                .preferredColorScheme(.dark)
        }
    }
}
