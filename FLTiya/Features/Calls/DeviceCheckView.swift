#if DEBUG
import AVFoundation
import SwiftUI
import UIKit

@MainActor
struct DeviceCheckView: View {
    let mode: DeviceCheckMode
    let ownerID: UUID
    let model: DeviceCheckModel
    let isAllowed: @MainActor () -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.socialRepository) private var repository
    @Environment(\.callCoordinator) private var calls
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 10) {
                        GameGlyph(symbol: "iphone", size: 24).accessibilityHidden(true)
                        Text("LOCAL DEVICE TEST").font(.caption.weight(.heavy)).tracking(2)
                    }.foregroundStyle(AppTheme.accent)
                    Text("No remote call. Nothing sent or recorded.")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                    if model.isStarting || model.isStopping {
                        ProgressView(model.isStopping ? "Stopping devices…" : "Starting devices…")
                    }
                    if let message = model.errorMessage {
                        Text(message).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    if model.needsSettings {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }.buttonStyle(.borderedProminent).foregroundStyle(AppTheme.onAccent)
                            .frame(minHeight: 44)
                    } else if !model.isRunning, !model.isStarting, !model.isStopping {
                        Button("Try device test again") { Task { await start() } }
                            .buttonStyle(.borderedProminent).foregroundStyle(AppTheme.onAccent)
                            .frame(minHeight: 44)
                    }
                    if mode == .video, model.errorMessage != nil { endTestButton }
                    if mode == .video { camera }
                    microphone
                    if mode != .video || model.errorMessage == nil { endTestButton }
                    Text("This checks your own hardware. A second device and a configured calling service are needed to test a real friend call.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }.padding(24)
            }
            .background { AppBackdrop() }
            .navigationTitle(mode.title)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { endTest() } }
            }
        }
        .interactiveDismissDisabled(model.isStarting || model.isRunning || model.isStopping)
        .task { await start() }
        .onChange(of: model.shouldDismiss) { _, value in if value { dismiss() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { endTest() } }
        .onChange(of: repository?.currentUserID) { _, userID in if userID != ownerID { endTest() } }
        .onChange(of: calls?.call?.id) { _, callID in if callID != nil { endTest() } }
        .onDisappear {
            model.invalidate()
            Task { await model.stop() }
        }
    }

    private var camera: some View {
        VStack(spacing: 12) {
            Group {
                if let session = model.cameraSession {
                    DeviceCameraPreview(session: session, isFrontCamera: model.isFrontCamera)
                } else {
                    ZStack {
                        Color.black
                        GameGlyph(symbol: "video.slash.fill", size: 48).foregroundStyle(.white)
                    }
                }
            }
            .frame(height: model.cameraSession == nil ? 170 : 340)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityLabel("Live preview from your own camera")
            Button {
                Task { await model.switchCamera() }
            } label: {
                SocialActionLabel(title: "Flip camera", symbol: "arrow.triangle.2.circlepath.camera")
            }.disabled(!model.isRunning || model.isSwitchingCamera)
        }
    }

    private var endTestButton: some View {
        Button("End test", role: .destructive) { endTest() }
            .frame(minHeight: 44)
    }

    private var microphone: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    GameGlyph(symbol: "mic.fill", size: 24).foregroundStyle(AppTheme.accent)
                    Text(model.isRunning ? "Microphone listening" : "Microphone not active")
                        .font(.headline).foregroundStyle(AppTheme.ink)
                }
                ProgressView(value: Double(model.microphoneLevel))
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Live microphone input level")
                    .accessibilityValue("\(Int(model.microphoneLevel * 100)) percent")
                Text("Speak and watch the input level move. Your voice isn't played back or saved.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }

    private func start() async {
        await model.start(mode: mode) {
            isAllowed() && repository?.currentUserID == ownerID && calls?.call == nil
                && scenePhase != .background
        }
    }

    private func endTest() {
        model.invalidate()
        Task { await model.stop(); dismiss() }
    }
}

private struct DeviceCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isFrontCamera: Bool

    func makeUIView(context: Context) -> DeviceCameraPreviewView {
        let view = DeviceCameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: DeviceCameraPreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
        guard let connection = view.previewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFrontCamera
        }
        view.updateOrientation()
    }

    static func dismantleUIView(_ view: DeviceCameraPreviewView, coordinator: ()) {
        view.previewLayer.session = nil
    }
}

private final class DeviceCameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer.connection else { return }
        let angle: CGFloat
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
}
#endif
