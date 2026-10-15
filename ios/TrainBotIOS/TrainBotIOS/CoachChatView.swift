import SwiftUI

struct CoachChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var messages: [ChatMessageItem] = [
        ChatMessageItem(
            role: "assistant",
            text: "Привет, Леонид! Я твой ИИ-тренер TrainBot v8.0. Можешь спросить план на сегодня («я в зале»), написать подходы («80 10»), записать приём пищи или попросить разбор InBody и прогрессии.",
            model: "TrainBot Coach v8.0",
            timestamp: Date()
        )
    ]
    @State private var inputText: String = ""
    @State private var isSending: Bool = false

    private let quickPrompts = [
        "Я в зале — что делаем сегодня?",
        "Разбери мой последний InBody",
        "Какой объём по мышцам за 7 дней?",
        "Разбор блока за 4 недели"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick prompt pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button {
                                Task { await sendMessage(prompt) }
                            } label: {
                                Text(prompt)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.cyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                chatBubble(msg)
                                    .id(msg.id)
                            }
                            if isSending {
                                HStack {
                                    ProgressView().tint(.cyan)
                                    Text("Тренер анализирует базу...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                HStack(spacing: 10) {
                    TextField("Напиши тренеру, вес×повторы или питание...", text: $inputText, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        let text = inputText
                        inputText = ""
                        Task { await sendMessage(text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .cyan)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(12)
                .background(Color(red: 0.06, green: 0.09, blue: 0.15))
            }
            .background(Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea())
            .navigationTitle("ИИ-Тренер (Единая память)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func chatBubble(_ msg: ChatMessageItem) -> some View {
        let isUser = msg.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(msg.text)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? .black : .white)

                if let model = msg.model, !isUser {
                    Text("🤖 \(model)")
                        .font(.caption2)
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
            .padding(14)
            .background(
                isUser ? Color.cyan : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18)
            )
            if !isUser { Spacer(minLength: 30) }
        }
    }

    private func sendMessage(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessageItem(role: "user", text: text, model: nil, timestamp: Date()))
        isSending = true
        defer { isSending = false }
        do {
            let res = try await appState.api.sendCoachMessage(text)
            messages.append(
                ChatMessageItem(
                    role: "assistant",
                    text: res.reply,
                    model: res.model,
                    timestamp: Date()
                )
            )
            if let brief = res.machineBrief {
                appState.activeBrief = brief
            }
            if let logged = res.loggedWorkouts, !logged.isEmpty {
                await appState.refreshBootstrap()
            }
        } catch {
            messages.append(
                ChatMessageItem(
                    role: "assistant",
                    text: "Ошибка связи с сервером: \(error.localizedDescription)",
                    model: "System",
                    timestamp: Date()
                )
            )
        }
    }
}
