import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct InBodyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var history: InBodyHistoryResponse?
    @State private var isLoading: Bool = false
    @State private var isUploading: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter: Bool = false
    @State private var inbodyCardImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Upload PDF or Photo of Printed InBody Sheet
                    uploadActionCard

                    if isUploading {
                        HStack(spacing: 12) {
                            ProgressView().tint(.cyan)
                            Text("ИИ-агент распознаёт 25+ показателей InBody и сегменты...")
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let comp = history?.comparison {
                        currentInBodyOverview(comp)
                        segmentalLeanCard(comp.current.segmentalLean)
                        if let diags = comp.diagnostics, !diags.isEmpty {
                            diagnosticsCard(diags)
                        }
                    } else if !isLoading {
                        Text("Загрузи PDF-отчёт или сфотографируй бумажный лист InBody для глубокого анализа сегментов и воды.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(24)
                    }

                    if let img = inbodyCardImage {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Инфографика InBody")
                                    .font(.headline)
                                Spacer()
                                ShareLink(item: Image(uiImage: img), preview: SharePreview("InBody Report", image: Image(uiImage: img))) {
                                    Label("Поделиться", systemImage: "square.and.arrow.up")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding()
            }
            .background(Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea())
            .navigationTitle("InBody · Состав тела")
            .task {
                await loadInBody()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem = newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await uploadInBodyData(data, mimeType: "image/jpeg", filename: "inbody_photo.jpg")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        let isPDF = url.pathExtension.lowercased() == "pdf"
                        Task {
                            await uploadInBodyData(
                                data,
                                mimeType: isPDF ? "application/pdf" : "image/jpeg",
                                filename: url.lastPathComponent
                            )
                        }
                    }
                }
            }
        }
    }

    private var uploadActionCard: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Фото бланка InBody", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Загрузить PDF", systemImage: "doc.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        }
    }

    private func currentInBodyOverview(_ comp: InBodyComparison) -> some View {
        let cur = comp.current
        let pd = comp.prevDeltas
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ТЕСТ INBODY ОТ \(cur.date)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(cur.deviceModel ?? "Анализ состава тела")
                        .font(.headline)
                }
                Spacer()
                if let score = cur.inbodyScore {
                    Text("\(score) / 100")
                        .font(.title3.weight(.heavy))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.2), in: Capsule())
                        .foregroundStyle(.cyan)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricBox("Вес", value: cur.weight, unit: "кг", delta: pd?.weight, color: .blue)
                metricBox("Мышцы (SMM)", value: cur.smm, unit: "кг", delta: pd?.smm, color: .green)
                metricBox("Жир (PBF)", value: cur.fatPct, unit: "%", delta: pd?.fatPct, color: .pink)
                metricBox("Масса жира", value: cur.fatKg, unit: "кг", delta: pd?.fatKg, color: .orange)
            }

            HStack(spacing: 16) {
                Text("Висцеральный: **\(cur.visceral.map(String.init) ?? "—")**")
                Text("BMR: **\(cur.bmrKcal.map { "\($0) ккал" } ?? "—")**")
                if let ecw = cur.ecwTbwRatio {
                    Text(String(format: "ECW/TBW: %.3f", ecw))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private func metricBox(_ label: String, value: Double?, unit: String, delta: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(value.map { String(format: "%.1f %@", $0, unit) } ?? "—")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
            if let d = delta {
                Text(String(format: "Δ пред: %+.1f %@", d, unit))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func segmentalLeanCard(_ seg: SegmentalLean?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("СЕГМЕНТАРНЫЙ БАЛАНС МЫШЦ")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            segmentRow("Правая рука", kg: seg?.rightArmKg, pct: seg?.rightArmPct)
            segmentRow("Левая рука", kg: seg?.leftArmKg, pct: seg?.leftArmPct)
            segmentRow("Корпус", kg: seg?.trunkKg, pct: seg?.trunkPct)
            segmentRow("Правая нога", kg: seg?.rightLegKg, pct: seg?.rightLegPct)
            segmentRow("Левая нога", kg: seg?.leftLegKg, pct: seg?.leftLegPct)
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private func segmentRow(_ title: String, kg: Double?, pct: Double?) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 95, alignment: .leading)
            GeometryReader { geo in
                let ratio = min(max((pct ?? 100.0) / 130.0, 0.2), 1.0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.green).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 10)
            Text(kg.map { String(format: "%.2f кг", $0) } ?? "—")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.cyan)
                .frame(width: 68, alignment: .trailing)
        }
    }

    private func diagnosticsCard(_ diags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ДИАГНОСТИКА АСИММЕТРИИ И ВОДЫ")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            ForEach(diags, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.cyan)
                    Text(line).font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func loadInBody() async {
        isLoading = true
        defer { isLoading = false }
        history = try? await appState.api.fetchInBodyHistory()
        if let data = try? await appState.api.fetchCardPNG(type: "inbody"),
           let uiImg = UIImage(data: data) {
            inbodyCardImage = uiImg
        }
    }

    private func uploadInBodyData(_ data: Data, mimeType: String, filename: String) async {
        isUploading = true
        defer { isUploading = false }
        do {
            _ = try await appState.api.uploadInBody(fileData: data, mimeType: mimeType, filename: filename)
            await loadInBody()
            await appState.refreshBootstrap()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
