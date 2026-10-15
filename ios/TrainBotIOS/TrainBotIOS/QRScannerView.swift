import SwiftUI
import AVFoundation

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var manualQuery: String = ""
    @State private var scannedCode: String?
    @State private var showBindPicker: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea()

                VStack(spacing: 16) {
                    ZStack {
                        QRCameraPreview { code in
                            guard scannedCode == nil else { return }
                            scannedCode = code
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            Task {
                                await handleScannedQR(code)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.cyan.opacity(0.7), lineWidth: 2)
                        )

                        // Target reticle overlay
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [14, 10]))
                            .foregroundStyle(.cyan)
                            .frame(width: 230, height: 230)

                        VStack {
                            Spacer()
                            Text("Наведи камеру на QR-код на раме тренажёра DDX")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 16)
                        }
                    }
                    .frame(maxHeight: 380)
                    .padding(.horizontal)

                    // Quick search / text input fallback
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ИЛИ НАПИШИ НАЗВАНИЕ ТРЕНАЖЁРА")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            TextField("Например: Pull Down, жим ногами, бабочка...", text: $manualQuery)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                            Button {
                                guard !manualQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                Task {
                                    await appState.activateMachine(query: manualQuery)
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 12)
            }
            .navigationTitle("Сканер тренажёра DDX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheet(isPresented: $showBindPicker) {
                if let code = scannedCode {
                    BindQRToEquipmentSheet(qrCode: code) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func handleScannedQR(_ code: String) async {
        do {
            let resolved = try await appState.api.resolveEquipment(qrPayload: code, activate: true)
            if resolved.status == "resolved" {
                appState.activeBrief = resolved
                dismiss()
            } else {
                // Unknown QR code — let user bind it once to one of the 212 DDX machines
                showBindPicker = true
            }
        } catch {
            showBindPicker = true
        }
    }
}

struct BindQRToEquipmentSheet: View {
    let qrCode: String
    let onBound: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var search: String = ""
    @State private var items: [EquipmentItem] = []

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    Task {
                        try? await appState.api.bindQR(qrCode: qrCode, equipmentId: item.id, label: item.exerciseName)
                        await appState.activateMachine(equipmentId: item.id)
                        dismiss()
                        onBound()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(item.ddxName ?? item.equipmentNameRu ?? "") · \(item.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Найти тренажёр в базе DDX (212 шт.)")
            .onChange(of: search) { _, newValue in
                Task { await load(query: newValue) }
            }
            .task {
                await load(query: "")
            }
            .navigationTitle("Привязать новый QR")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func load(query: String) async {
        items = (try? await appState.api.fetchEquipment(query: query)) ?? []
    }
}

// MARK: - AVFoundation Camera UIViewRepresentable

struct QRCameraPreview: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraViewController {
        let vc = QRCameraViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRCameraViewController, context: Context) {}
}

final class QRCameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCamera() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else {
            return
        }
        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr, .ean13, .code128]
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.frame = view.layer.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        self.previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = readable.stringValue,
              !stringValue.isEmpty else { return }
        captureSession.stopRunning()
        onCodeScanned?(stringValue)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}
