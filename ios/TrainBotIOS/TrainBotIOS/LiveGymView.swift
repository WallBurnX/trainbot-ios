import SwiftUI

struct LiveGymView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showQRScanner: Bool = false
    @State private var customWeight: String = "80"
    @State private var customReps: String = "10"
    @State private var customRIR: String = "2"
    @State private var quickTextCommand: String = ""
    @State private var workoutCardImage: UIImage?
    @State private var showWorkoutCardSheet: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Hero QR / Camera / Quick-Text Bar
                    scannerHeroCard

                    // 2. Active Gym Machine Card (if selected)
                    if let brief = appState.activeBrief {
                        activeMachineCard(brief)
                    } else {
                        emptyActiveMachineBanner
                    }

                    // 3. Today's Logged Sets
                    todayWorkoutLogSection
                }
                .padding()
            }
            .background(Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea())
            .navigationTitle("В зале · Live Logger")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await renderTodaySummaryCard() }
                    } label: {
                        Label("Итог PNG", systemImage: "photo.badge.checkmark")
                    }
                }
            }
            .refreshable {
                await appState.refreshBootstrap()
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet()
            }
            .sheet(isPresented: $showWorkoutCardSheet) {
                if let img = workoutCardImage {
                    NavigationStack {
                        ScrollView {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                        .background(Color.black.ignoresSafeArea())
                        .navigationTitle("Итог тренировки")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                ShareLink(item: Image(uiImage: img), preview: SharePreview("Тренировка TrainBot", image: Image(uiImage: img)))
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { showWorkoutCardSheet = false }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Scanner Hero Card

    private var scannerHeroCard: some View {
        VStack(spacing: 12) {
            Button {
                showQRScanner = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(12)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Сканировать QR тренажёра DDX")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Подтянет прошлые веса, рекорд и цель на сегодня")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.cyan)
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.22), Color.blue.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1.5)
                )
            }

            // Shorthand / Natural Language Quick Bar
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                TextField("Быстрый ввод: «80 10», «80х10 85х8» или «сел на жим ногами»", text: $quickTextCommand)
                    .font(.subheadline)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await sendQuickCommand() }
                    }
                if !quickTextCommand.isEmpty {
                    Button {
                        Task { await sendQuickCommand() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Active Machine Card

    private func activeMachineCard(_ brief: MachineResolveResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                if let eqId = brief.equipmentId ?? brief.equipment?.id,
                   let url = appState.api.equipmentImageURL(for: eqId) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color.white.opacity(0.08)
                                .overlay(Image(systemName: "dumbbell.fill").foregroundStyle(.cyan))
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("АКТИВНЫЙ ТРЕНАЖЁР · \((brief.muscleLabel ?? "СИЛОВАЯ").uppercased())")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.cyan)

                    Text(brief.exerciseName ?? brief.ddxName ?? "Тренажёр")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    if let ddx = brief.ddxName {
                        Text(ddx)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let pb = brief.personalBest?.text {
                        Text("🏆 Рекорд: \(pb)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(.top, 2)
                    }
                }
                Spacer()
            }

            // Target Prescription Banner
            if let target = brief.target {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ЦЕЛЬ НА СЕГОДНЯ")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text("RIR \(target.rir ?? 2) · Отдых \(target.restSeconds ?? 120)с")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(target.loadText ?? "Подбор веса")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(target.sets ?? 3) × \(target.reps ?? "8-12")")
                            .font(.headline)
                            .foregroundStyle(.cyan)
                    }
                    if let why = target.why, !why.isEmpty {
                        Text(why)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                )
            }

            // 1-Tap Quick Set Buttons
            if let buttons = brief.quickButtons, !buttons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ЗАПИСАТЬ ПОДХОД В 1 КАСАНИЕ:")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(buttons) { btn in
                            Button {
                                customWeight = btn.weight
                                customReps = "\(btn.reps)"
                                Task {
                                    await appState.logSet(weight: btn.weight, reps: "\(btn.reps)")
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text("✅ \(btn.weight) кг")
                                        .font(.subheadline.weight(.bold))
                                    Text("× \(btn.reps) повт.")
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.green.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.green.opacity(0.6), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }

            // Custom Weight / Reps Stepper Row
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Вес (кг)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("80", text: $customWeight)
                        .keyboardType(.decimalPad)
                        .font(.headline)
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Повторы")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("10", text: $customReps)
                        .keyboardType(.numberPad)
                        .font(.headline)
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("RIR")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("2", text: $customRIR)
                        .keyboardType(.numberPad)
                        .font(.headline)
                        .frame(width: 52)
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    Task {
                        await appState.logSet(weight: customWeight, reps: customReps, rir: customRIR)
                    }
                } label: {
                    Text("+ Сет")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                .padding(.top, 14)
            }

            // Recent History on this Machine
            if let history = brief.history, !history.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ПРОШЛЫЕ ТРЕНИРОВКИ НА ЭТОМ ТРЕНАЖЁРЕ:")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(history.prefix(3)) { h in
                        HStack {
                            Text(h.date)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.cyan)
                            Text(h.setsText)
                                .font(.caption)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                }
            }

            // Occupied Machine Alternatives
            if let alts = brief.alternatives, !alts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("🔄 ТРЕНАЖЁР ЗАНЯТ? ЗАМЕНЫ В DDX:")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(alts) { alt in
                                Button {
                                    Task {
                                        await appState.activateMachine(equipmentId: alt.equipmentId, query: alt.exerciseName)
                                    }
                                } label: {
                                    Text(alt.exerciseName)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.orange.opacity(0.16), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .onAppear {
            if let w = brief.target?.weightKg {
                customWeight = String(format: "%g", w)
            }
        }
    }

    private var emptyActiveMachineBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Тренажёр ещё не выбран")
                .font(.headline)
            Text("Отсканируй QR-код на раме тренажёра, выбери его во вкладке «Тренажёры» или напиши в строку выше: «сел на жим от груди».")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Today's Workout Log Section

    private var todayWorkoutLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Журнал за сегодня")
                    .font(.headline)
                Spacer()
                Text("Тоннаж: \(Int(appState.todayTonnage)) кг")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.cyan)
            }

            if appState.todayWorkouts.isEmpty {
                Text("За сегодня пока нет записанных подходов.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.todayWorkouts, id: \.stableId) { w in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(w.exercise)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(w.weight ?? "—") кг × \(w.reps ?? "—") (\(w.sets ?? 1) подх.) · \(Int(w.tonnage ?? 0)) кг")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                        if let wid = w.id {
                            Button(role: .destructive) {
                                Task { await appState.undoSet(workoutId: wid) }
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.title3)
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }

    private func sendQuickCommand() async {
        let text = quickTextCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        quickTextCommand = ""
        do {
            let res = try await appState.api.sendCoachMessage(text)
            if let brief = res.machineBrief {
                appState.activeBrief = brief
            }
            await appState.refreshBootstrap()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func renderTodaySummaryCard() async {
        if let data = try? await appState.api.fetchCardPNG(type: "workout"),
           let img = UIImage(data: data) {
            workoutCardImage = img
            showWorkoutCardSheet = true
        }
    }
}
