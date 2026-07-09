import SwiftUI
import AVFoundation

enum BarcodeScanMode {
    case food
    case supplement
}

struct BarcodeScannerScreen: View {
    @ObservedObject var viewModel: MainViewModel
    let mode: BarcodeScanMode
    @Environment(\.dismiss) private var dismiss
    @State private var scannedBarcode: String?
    @State private var cameraPermissionDenied = false
    @State private var readyToScan = false

    var body: some View {
        ZStack {
            if cameraPermissionDenied {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Доступ к камере запрещён")
                        .font(.headline)
                    Text("Разрешите доступ к камере в Настройках")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else {
                BarcodeScannerView(isEnabled: readyToScan) { barcode in
                    guard scannedBarcode == nil else { return }
                    readyToScan = false
                    scannedBarcode = barcode
                    switch mode {
                    case .food:
                        viewModel.onBarcodeScanned(barcode)
                    case .supplement:
                        viewModel.onSupplementBarcodeScanned(barcode)
                    }
                    dismiss()
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Button(action: { readyToScan = true }) {
                        Label(
                            readyToScan ? "Наведите на штрих-код…" : "Сканировать",
                            systemImage: readyToScan ? "barcode.viewfinder" : "barcode.viewfinder"
                        )
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(readyToScan ? Color.green : Color.blue)
                        .cornerRadius(14)
                        .padding(.horizontal, 32)
                    }
                    .disabled(readyToScan)
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationTitle(mode == .food ? "Сканер штрих-кода" : "Сканер БАД")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkCameraPermission() }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraPermissionDenied = !granted }
            }
        default:
            cameraPermissionDenied = true
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    var isEnabled: Bool
    let onBarcodeFound: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onBarcodeFound = onBarcodeFound
        vc.isEnabled = isEnabled
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        uiViewController.isEnabled = isEnabled
    }
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onBarcodeFound: ((String) -> Void)?
    var isEnabled: Bool = false

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .code93, .itf14, .qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isEnabled,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = object.stringValue else { return }
        isEnabled = false
        captureSession?.stopRunning()
        onBarcodeFound?(barcode)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
