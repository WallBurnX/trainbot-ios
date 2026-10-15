import SwiftUI

struct EquipmentCatalogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [EquipmentItem] = []
    @State private var searchText: String = ""
    @State private var selectedCategory: String = ""
    @State private var isLoading: Bool = false

    private let categories: [(label: String, code: String)] = [
        ("Все (212)", ""),
        ("Грудь", "chest"),
        ("Спина", "back"),
        ("Ноги", "legs"),
        ("Плечи", "shoulders"),
        ("Руки", "arms"),
        ("Кор", "core"),
        ("Кардио", "cardio")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.code) { cat in
                            Button {
                                selectedCategory = cat.code
                                Task { await loadCatalog() }
                            } label: {
                                Text(cat.label)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedCategory == cat.code ? Color.cyan : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedCategory == cat.code ? .black : .white)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                if isLoading && items.isEmpty {
                    Spacer()
                    ProgressView("Загружаю каталог DDX...")
                    Spacer()
                } else {
                    List(items) { item in
                        Button {
                            Task {
                                await appState.activateMachine(equipmentId: item.id)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                if let url = appState.api.equipmentImageURL(for: item.id) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            Color.white.opacity(0.08)
                                                .overlay(Image(systemName: "dumbbell").foregroundStyle(.secondary))
                                        }
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.exerciseName)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text(item.ddxName ?? item.equipmentNameRu ?? item.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: 8) {
                                        if let last = item.lastWorkout, let w = last.weight {
                                            Text("Прошлый: \(w) кг × \(last.reps ?? "—")")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.cyan)
                                        }
                                        if item.boundQr != nil {
                                            Label("QR привязан", systemImage: "qrcode")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color(red: 0.07, green: 0.10, blue: 0.16))
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea())
            .navigationTitle("Каталог DDX (\(items.count))")
            .searchable(text: $searchText, prompt: "Поиск по 212 тренажёрам и упражнениям")
            .onChange(of: searchText) { _, _ in
                Task { await loadCatalog() }
            }
            .task {
                if items.isEmpty {
                    await loadCatalog()
                }
            }
        }
    }

    private func loadCatalog() async {
        isLoading = true
        defer { isLoading = false }
        items = (try? await appState.api.fetchEquipment(query: searchText, category: selectedCategory)) ?? []
    }
}
