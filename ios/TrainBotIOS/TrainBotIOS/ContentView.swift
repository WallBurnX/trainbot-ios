import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var apiClient: TrainBotAPIClient

    var body: some View {
        Group {
            if apiClient.isAuthenticated {
                mainTabs
            } else {
                LoginView()
            }
        }
        .task {
            if apiClient.isAuthenticated {
                await appState.refreshBootstrap()
            }
        }
        .onChange(of: apiClient.isAuthenticated) { _, authed in
            if authed {
                Task { await appState.refreshBootstrap() }
            }
        }
    }

    private var mainTabs: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $appState.selectedTab) {
                LiveGymView()
                    .tabItem {
                        Label("В зале", systemImage: "qrcode.viewfinder")
                    }
                    .tag(0)

                EquipmentCatalogView()
                    .tabItem {
                        Label("Тренажёры", systemImage: "dumbbell.fill")
                    }
                    .tag(1)

                CoachChatView()
                    .tabItem {
                        Label("Тренер ИИ", systemImage: "brain.head.profile")
                    }
                    .tag(2)

                InBodyView()
                    .tabItem {
                        Label("InBody", systemImage: "figure.arms.open")
                    }
                    .tag(3)

                DashboardHealthView()
                    .tabItem {
                        Label("Здоровье", systemImage: "heart.text.square.fill")
                    }
                    .tag(4)
            }
            .tint(.cyan)

            if appState.timerManager.isRunning {
                FloatingRestTimerBar()
                    .padding(.bottom, 56)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Floating Rest Timer Bar

struct FloatingRestTimerBar: View {
    @ObservedObject var timer = RestTimerManager.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    .frame(width: 42, height: 42)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 42, height: 42)
                Text(timer.formattedRemaining)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("ОТДЫХ МЕЖДУ ПОДХОДАМИ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
                Text("\(timer.exerciseName) · \(timer.nextTargetText)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button("+30с") {
                timer.addSeconds(30)
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: Capsule())

            Button {
                timer.stop()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.08, green: 0.13, blue: 0.22).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.cyan.opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject private var apiClient: TrainBotAPIClient
    @State private var password: String = ""
    @State private var serverURL: String = TrainBotAPIClient.shared.baseURL
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.10),
                    Color(red: 0.07, green: 0.12, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.cyan)
                    .padding(22)
                    .background(Color.cyan.opacity(0.14), in: Circle())

                VStack(spacing: 6) {
                    Text("TrainBot iOS v8.0")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(.white)
                    Text("Персональный ИИ-тренер · DDX QR · InBody · Apple Health")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("СЕРВЕР TRAINBOT CRM")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    TextField("https://fitness.wallburn.fun", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                    Text("ПАРОЛЬ ВЛАДЕЛЬЦА CRM")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    SecureField("Введи пароль от fitness.wallburn.fun", text: $password)
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                if let errorText = errorText {
                    Text(errorText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "lock.open.fill")
                            Text("Войти и синхронизировать с VPS")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
                }
                .disabled(isSubmitting || password.isEmpty)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func signIn() async {
        isSubmitting = true
        errorText = nil
        apiClient.baseURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await apiClient.login(password: password)
        } catch {
            errorText = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Dashboard & Apple Health View

struct DashboardHealthView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var healthKit = HealthKitManager.shared
    @State private var weeklyCardImage: UIImage?
    @State private var isRenderingCard: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // KPI Row
                    HStack(spacing: 12) {
                        kpiTile(
                            title: "ВЕС ТЕЛА",
                            value: appState.bootstrap?.latestMeasurement?.weight.map { String(format: "%.1f кг", $0) } ?? "—",
                            subtitle: "SMM: \(appState.bootstrap?.latestMeasurement?.smm.map { String(format: "%.1f кг", $0) } ?? "—")",
                            color: .cyan
                        )
                        kpiTile(
                            title: "ТОННАЖ СЕГОДНЯ",
                            value: "\(Int(appState.todayTonnage)) кг",
                            subtitle: "Сетов: \(appState.todayWorkouts.count)",
                            color: .green
                        )
                    }

                    HStack(spacing: 12) {
                        kpiTile(
                            title: "КАЛОРИИ СЕГОДНЯ",
                            value: "\(Int(appState.bootstrap?.todayMacros.calories ?? 0)) ккал",
                            subtitle: "Белок: \(Int(appState.bootstrap?.todayMacros.proteins ?? 0)) г",
                            color: .orange
                        )
                        kpiTile(
                            title: "СОН / ШАГИ",
                            value: appState.bootstrap?.todayWellness?.sleepHours.map { String(format: "%.1f ч", $0) } ?? "—",
                            subtitle: "Шаги: \(appState.bootstrap?.todayWellness?.steps ?? 0)",
                            color: .purple
                        )
                    }

                    // Apple HealthKit Sync Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                            Text("Синхронизация с Apple Health & Watch")
                                .font(.headline)
                            Spacer()
                        }
                        Text("Автоматически передаёт утренний вес, шаги, часы сна, пульс покоя (RHR), HRV и активные калории в твой TrainBot CRM на VPS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(healthKit.lastSyncSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)

                        Button {
                            Task {
                                await healthKit.requestAuthorizationAndSync()
                                await appState.refreshBootstrap()
                            }
                        } label: {
                            HStack {
                                if healthKit.isSyncing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    Text("Синхронизировать Apple Health сейчас")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.pink.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))

                    // Weekly Infographic Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Инфографика недели (PNG 1080p)")
                                .font(.headline)
                            Spacer()
                            Button {
                                Task { await loadWeeklyCard() }
                            } label: {
                                Label("Обновить", systemImage: "sparkles")
                                    .font(.caption.weight(.bold))
                            }
                        }

                        if isRenderingCard {
                            ProgressView("Генерирую карточку недели...")
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else if let img = weeklyCardImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                }
                .padding()
            }
            .background(Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea())
            .navigationTitle("Здоровье & Статус")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Выйти") {
                        appState.api.logout()
                    }
                    .foregroundStyle(.red)
                }
            }
            .task {
                if weeklyCardImage == nil {
                    await loadWeeklyCard()
                }
            }
        }
    }

    private func kpiTile(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private func loadWeeklyCard() async {
        isRenderingCard = true
        defer { isRenderingCard = false }
        if let data = try? await appState.api.fetchCardPNG(type: "week"),
           let uiImg = UIImage(data: data) {
            weeklyCardImage = uiImg
        }
    }
}
