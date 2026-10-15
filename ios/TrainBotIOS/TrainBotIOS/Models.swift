import Foundation

// MARK: - Auth & Bootstrap Models

struct AuthTokenResponse: Codable {
    let success: Bool
    let token: String
    let tokenType: String
    let expiresAt: String
    let deviceName: String
    let version: String?

    enum CodingKeys: String, CodingKey {
        case success, token, version
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case deviceName = "device_name"
    }
}

struct BootstrapResponse: Codable {
    let status: String
    let serverTime: String
    let today: String
    let version: String
    let latestMeasurement: MeasurementRecord?
    let inbody: InBodyComparison?
    let activeMachine: ActiveMachineState?
    let activeMachineBrief: MachineResolveResponse?
    let todayWorkouts: [WorkoutRecord]
    let todayTonnage: Double
    let todayMacros: MacroSummary
    let todayWellness: WellnessRecord?
    let equipmentCount: Int

    enum CodingKeys: String, CodingKey {
        case status, today, version, inbody
        case serverTime = "server_time"
        case latestMeasurement = "latest_measurement"
        case activeMachine = "active_machine"
        case activeMachineBrief = "active_machine_brief"
        case todayWorkouts = "today_workouts"
        case todayTonnage = "today_tonnage"
        case todayMacros = "today_macros"
        case todayWellness = "today_wellness"
        case equipmentCount = "equipment_count"
    }
}

struct MacroSummary: Codable {
    let calories: Double
    let proteins: Double
    let fats: Double
    let carbs: Double
}

struct MeasurementRecord: Codable {
    let date: String?
    let weight: Double?
    let smm: Double?
    let fatKg: Double?
    let fatPct: Double?
    let visceral: Int?
    let waist: Double?
    let abdomen: Double?
    let chest: Double?

    enum CodingKeys: String, CodingKey {
        case date, weight, smm, visceral, waist, abdomen, chest
        case fatKg = "fat_kg"
        case fatPct = "fat_pct"
    }
}

struct WellnessRecord: Codable {
    let date: String?
    let sleepHours: Double?
    let sleepQuality: Int?
    let steps: Int?
    let waterL: Double?
    let mood: Int?
    let energy: Int?
    let restingPulse: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case date, steps, mood, energy, notes
        case sleepHours = "sleep_hours"
        case sleepQuality = "sleep_quality"
        case waterL = "water_l"
        case restingPulse = "resting_pulse"
    }
}

// MARK: - Equipment & Active Machine Models

struct EquipmentItem: Codable, Identifiable, Hashable {
    let id: String
    let exerciseName: String
    let ddxName: String?
    let equipmentNameRu: String?
    let equipmentNameEn: String?
    let category: String?
    let primaryMuscles: String?
    let imageUrl: String?
    let boundQr: String?
    let lastWorkout: LastWorkoutSnippet?

    enum CodingKeys: String, CodingKey {
        case id, category
        case exerciseName = "exercise_name"
        case ddxName = "ddx_name"
        case equipmentNameRu = "equipment_name_ru"
        case equipmentNameEn = "equipment_name_en"
        case primaryMuscles = "primary_muscles"
        case imageUrl = "image_url"
        case boundQr = "bound_qr"
        case lastWorkout = "last_workout"
    }
}

struct LastWorkoutSnippet: Codable, Hashable {
    let weight: String?
    let sets: Int?
    let reps: String?
    let date: String?
}

struct EquipmentListResponse: Codable {
    let count: Int
    let items: [EquipmentItem]
}

struct ActiveMachineState: Codable {
    let equipmentId: String?
    let exerciseName: String?
    let ddxName: String?
    let activatedAt: String?

    enum CodingKeys: String, CodingKey {
        case equipmentId = "equipment_id"
        case exerciseName = "exercise_name"
        case ddxName = "ddx_name"
        case activatedAt = "activated_at"
    }
}

struct MachineTarget: Codable {
    let loadText: String?
    let weightKg: Double?
    let sets: Int?
    let reps: String?
    let rir: Int?
    let restSeconds: Int?
    let decision: String?
    let why: String?

    enum CodingKeys: String, CodingKey {
        case sets, reps, rir, decision, why
        case loadText = "load_text"
        case weightKg = "weight_kg"
        case restSeconds = "rest_seconds"
    }
}

struct QuickSetButton: Codable, Identifiable, Hashable {
    var id: String { "\(weight)x\(reps)" }
    let label: String
    let weight: String
    let reps: Int
}

struct MachineHistoryItem: Codable, Identifiable {
    var id: String { date + setsText }
    let date: String
    let setsText: String
    let topWeight: Double?
    let topReps: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case setsText = "sets_text"
        case topWeight = "top_weight"
        case topReps = "top_reps"
    }
}

struct MachineAlternative: Codable, Identifiable {
    var id: String { equipmentId ?? exerciseName }
    let equipmentId: String?
    let exerciseName: String
    let ddxName: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case reason
        case equipmentId = "equipment_id"
        case exerciseName = "exercise_name"
        case ddxName = "ddx_name"
    }
}

struct PersonalBestInfo: Codable {
    let weight: Double?
    let reps: Int?
    let e1rm: Double?
    let date: String?
    let text: String?
}

struct MachineResolveResponse: Codable {
    let status: String
    let source: String?
    let qrStatus: String?
    let qrPayload: String?
    let equipmentId: String?
    let exerciseName: String?
    let ddxName: String?
    let equipmentNameEn: String?
    let muscleLabel: String?
    let equipment: EquipmentItem?
    let target: MachineTarget?
    let quickButtons: [QuickSetButton]?
    let history: [MachineHistoryItem]?
    let personalBest: PersonalBestInfo?
    let alternatives: [MachineAlternative]?
    let markdown: String?

    enum CodingKeys: String, CodingKey {
        case status, source, equipment, target, history, alternatives, markdown
        case qrStatus = "qr_status"
        case qrPayload = "qr_payload"
        case equipmentId = "equipment_id"
        case exerciseName = "exercise_name"
        case ddxName = "ddx_name"
        case equipmentNameEn = "equipment_name_en"
        case muscleLabel = "muscle_label"
        case quickButtons = "quick_buttons"
        case personalBest = "personal_best"
    }
}

// MARK: - Workout Models

struct WorkoutRecord: Codable, Identifiable {
    let id: Int?
    let date: String
    let time: String?
    let exercise: String
    let equipmentId: String?
    let weight: String?
    let sets: Int?
    let reps: String?
    let tonnage: Double?
    let comment: String?

    var stableId: String {
        if let id = id { return "w-\(id)" }
        return "\(date)-\(time ?? "")-\(exercise)-\(weight ?? "")-\(reps ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case id, date, time, exercise, weight, sets, reps, tonnage, comment
        case equipmentId = "equipment_id"
    }
}

struct QuickSetResponse: Codable {
    let success: Bool
    let workoutId: Int
    let logged: WorkoutRecord
    let todayTonnage: Double
    let todayWorkouts: [WorkoutRecord]

    enum CodingKeys: String, CodingKey {
        case success, logged
        case workoutId = "workout_id"
        case todayTonnage = "today_tonnage"
        case todayWorkouts = "today_workouts"
    }
}

// MARK: - InBody Models

struct SegmentalLean: Codable {
    let rightArmKg: Double?
    let rightArmPct: Double?
    let leftArmKg: Double?
    let leftArmPct: Double?
    let trunkKg: Double?
    let trunkPct: Double?
    let rightLegKg: Double?
    let rightLegPct: Double?
    let leftLegKg: Double?
    let leftLegPct: Double?

    enum CodingKeys: String, CodingKey {
        case rightArmKg = "right_arm_kg"
        case rightArmPct = "right_arm_pct"
        case leftArmKg = "left_arm_kg"
        case leftArmPct = "left_arm_pct"
        case trunkKg = "trunk_kg"
        case trunkPct = "trunk_pct"
        case rightLegKg = "right_leg_kg"
        case rightLegPct = "right_leg_pct"
        case leftLegKg = "left_leg_kg"
        case leftLegPct = "left_leg_pct"
    }
}

struct InBodyTestRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    let time: String?
    let deviceModel: String?
    let inbodyScore: Int?
    let weight: Double?
    let smm: Double?
    let fatKg: Double?
    let fatPct: Double?
    let bmi: Double?
    let visceral: Int?
    let bmrKcal: Int?
    let whr: Double?
    let tbwL: Double?
    let icwL: Double?
    let ecwL: Double?
    let ecwTbwRatio: Double?
    let proteinKg: Double?
    let mineralsKg: Double?
    let targetWeight: Double?
    let weightControl: Double?
    let fatControl: Double?
    let muscleControl: Double?
    let segmentalLean: SegmentalLean?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case date, time, weight, smm, bmi, visceral, whr, notes
        case deviceModel = "device_model"
        case inbodyScore = "inbody_score"
        case fatKg = "fat_kg"
        case fatPct = "fat_pct"
        case bmrKcal = "bmr_kcal"
        case tbwL = "tbw_l"
        case icwL = "icw_l"
        case ecwL = "ecw_l"
        case ecwTbwRatio = "ecw_tbw_ratio"
        case proteinKg = "protein_kg"
        case mineralsKg = "minerals_kg"
        case targetWeight = "target_weight"
        case weightControl = "weight_control"
        case fatControl = "fat_control"
        case muscleControl = "muscle_control"
        case segmentalLean = "segmental_lean"
    }
}

struct InBodyDeltas: Codable {
    let fromDate: String?
    let weight: Double?
    let smm: Double?
    let fatKg: Double?
    let fatPct: Double?
    let visceral: Double?
    let inbodyScore: Double?
    let ecwTbwRatio: Double?

    enum CodingKeys: String, CodingKey {
        case weight, smm, visceral
        case fromDate = "from_date"
        case fatKg = "fat_kg"
        case fatPct = "fat_pct"
        case inbodyScore = "inbody_score"
        case ecwTbwRatio = "ecw_tbw_ratio"
    }
}

struct InBodyComparison: Codable {
    let status: String?
    let current: InBodyTestRecord
    let previous: InBodyTestRecord?
    let baseline: InBodyTestRecord?
    let prevDeltas: InBodyDeltas?
    let baselineDeltas: InBodyDeltas?
    let diagnostics: [String]?

    enum CodingKeys: String, CodingKey {
        case status, current, previous, baseline, diagnostics
        case prevDeltas = "prev_deltas"
        case baselineDeltas = "baseline_deltas"
    }
}

struct InBodyHistoryResponse: Codable {
    let status: String
    let comparison: InBodyComparison?
    let tests: [InBodyTestRecord]
    let markdown: String?
}

struct InBodyUploadResponse: Codable {
    let success: Bool
    let saved: InBodyTestRecord
    let comparison: InBodyComparison
    let markdown: String
}

// MARK: - Chat Models

struct ChatMessageItem: Identifiable, Equatable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let text: String
    let model: String?
    let timestamp: Date
    var cardType: String?
}

struct CoachChatResponse: Codable {
    let reply: String
    let model: String?
    let type: String?
    let activeMachine: ActiveMachineState?
    let machineBrief: MachineResolveResponse?
    let loggedWorkouts: [WorkoutRecord]?

    enum CodingKeys: String, CodingKey {
        case reply, model, type
        case activeMachine = "active_machine"
        case machineBrief = "machine_brief"
        case loggedWorkouts = "logged_workouts"
    }
}
