#if DEBUG
import AVFoundation
import Foundation
import Observation

enum DeviceCheckMode: String, Identifiable, Sendable {
    case voice, video
    var id: String { rawValue }
    var title: String { self == .video ? "Video device test" : "Voice device test" }
}

/// A local hardware check. It never creates a friend, call, recording or network request.
@MainActor
@Observable
final class DeviceCheckModel {
    private(set) var isStarting = false
    private(set) var isRunning = false
    private(set) var isStopping = false
    private(set) var isSwitchingCamera = false
    private(set) var microphoneLevel: Float = 0
    private(set) var isFrontCamera = true
    private(set) var cameraSession: AVCaptureSession?
    private(set) var errorMessage: String?
    private(set) var needsSettings = false
    private(set) var shouldDismiss = false

    private static weak var activeOwner: DeviceCheckModel?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var worker: DeviceCaptureWorker?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var observations: [NSObjectProtocol] = []
    @ObservationIgnored private var canContinue: (@MainActor () -> Bool)?

    /// The real-call coordinator awaits this before taking ownership of AVAudioSession.
    static func stopActiveCheck() async {
        if let owner = activeOwner { await owner.stop() }
    }

    func start(mode: DeviceCheckMode, isAllowed: @escaping @MainActor () -> Bool) async {
        guard !isStarting, !isRunning, !isStopping, !Task.isCancelled, isAllowed() else { return }
        await stop(dismiss: false)
        guard !Task.isCancelled, isAllowed() else { return }

        let request = UUID()
        generation = request
        shouldDismiss = false
        errorMessage = nil
        needsSettings = false
        isStarting = true
        canContinue = isAllowed
        defer { if generation == request { isStarting = false } }

        // A replacement check must wait until its predecessor releases both devices.
        while let previous = Self.activeOwner, previous !== self {
            await previous.stop()
            guard isCurrent(request), isAllowed() else { return }
        }
        Self.activeOwner = self

        do {
            try await requirePermission(.audio)
            guard await continueOrStop(request, isAllowed: isAllowed) else { return }
            if mode == .video {
                try await requirePermission(.video)
                guard await continueOrStop(request, isAllowed: isAllowed) else { return }
            }

            let capture = DeviceCaptureWorker()
            worker = capture
            cameraSession = mode == .video ? capture.cameraSession : nil
            let front = try await capture.start(video: mode == .video) { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request, self.isRunning else { return }
                    guard self.canContinue?() == true else { await self.stop(); return }
                    self.microphoneLevel = level
                }
            }
            guard await continueOrStop(request, isAllowed: isAllowed) else { return }
            isFrontCamera = front
            isRunning = true
            observeInterruptions(capture: capture, request: request)
        } catch {
            guard generation == request else { return }
            let failure = error as? DeviceCheckFailure
            let permissionDenied = failure == .microphoneDenied || failure == .cameraDenied
            let message = failure?.message
                ?? "Couldn't start this device check. Close other apps using your microphone or camera and try again."
            await stop(dismiss: false)
            // A stop requested by a real call or sign-out must not revive this screen.
            guard !shouldDismiss, isAllowed() else { return }
            errorMessage = message
            needsSettings = permissionDenied
        }
    }

    /// Synchronously retires pending permission/capture completions before UI removal.
    func invalidate() {
        generation = UUID()
        isStarting = false
        isRunning = false
        isSwitchingCamera = false
        microphoneLevel = 0
        cameraSession = nil
        shouldDismiss = true
        canContinue = nil
    }

    func stop(dismiss: Bool = true) async {
        let wasDismissing = shouldDismiss
        invalidate()
        shouldDismiss = wasDismissing || dismiss
        observations.forEach { NotificationCenter.default.removeObserver($0) }
        observations = []
        if let cleanup { await cleanup.value; return }

        let ownedCapture = worker
        worker = nil
        isStopping = true
        // This cleanup task has fresh cancellation state and retains the worker
        // until its serial queue has actually stopped capture and audio input.
        let task = Task { if let ownedCapture { await ownedCapture.stop() } }
        cleanup = task
        await task.value
        cleanup = nil
        isStopping = false
        if Self.activeOwner === self { Self.activeOwner = nil }
    }

    func switchCamera() async {
        guard isRunning, !isSwitchingCamera, let worker, canContinue?() == true else { return }
        let request = generation
        isSwitchingCamera = true
        defer { if generation == request { isSwitchingCamera = false } }
        do {
            let front = try await worker.switchCamera()
            guard generation == request else { return }
            guard isCurrent(request), canContinue?() == true else { await stop(); return }
            isFrontCamera = front
        } catch {
            if generation == request { errorMessage = "Another camera isn't available on this device." }
        }
    }

    private func isCurrent(_ request: UUID) -> Bool {
        generation == request && !Task.isCancelled && !shouldDismiss
    }

    private func continueOrStop(_ request: UUID, isAllowed: @MainActor () -> Bool) async -> Bool {
        // A late permission/start result may never stop its replacement check.
        guard generation == request else { return false }
        guard isCurrent(request), isAllowed() else { await stop(); return false }
        return true
    }

    private func requirePermission(_ type: AVMediaType) async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: type)
        default: granted = false
        }
        guard granted else {
            throw type == .video ? DeviceCheckFailure.cameraDenied : DeviceCheckFailure.microphoneDenied
        }
    }

    private func observeInterruptions(capture: DeviceCaptureWorker, request: UUID) {
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    == AVAudioSession.InterruptionType.began.rawValue
                guard began else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    await self.stop()
                }
            })
        observations.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
            object: capture.cameraSession, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    await self.stop()
                }
            })
        observations.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
            object: capture.cameraSession, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    await self.stop()
                }
            })
        observations.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] notification in
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                    || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    await self.stop()
                }
            })
    }
}

private enum DeviceCheckFailure: Error, Equatable {
    case microphoneDenied, cameraDenied, microphoneUnavailable, cameraUnavailable
    var message: String {
        switch self {
        case .microphoneDenied: "Allow microphone access in Settings to test voice input."
        case .cameraDenied: "Allow camera access in Settings to test video."
        case .microphoneUnavailable: "A microphone isn't available on this device. Try a physical iPhone."
        case .cameraUnavailable: "A camera isn't available on this device. Try a physical iPhone."
        }
    }
}

/// AVFoundation's blocking configuration, start and stop APIs live on one queue.
/// The preview layer may bind the immutable session reference on the main thread;
/// every session mutation and all engine access stay confined to `queue`.
private final class DeviceCaptureWorker: @unchecked Sendable {
    let cameraSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.fltiya.device-check.capture", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var cameraInput: AVCaptureDeviceInput?
    private var hasTap = false
    private var ownsAudioSession = false
    private var previousAudioSettings: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    func start(video: Bool, onLevel: @escaping @Sendable (Float) -> Void) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let audio = AVAudioSession.sharedInstance()
                    self.previousAudioSettings = (audio.category, audio.mode, audio.categoryOptions)
                    try audio.setCategory(.record, mode: .measurement)
                    try audio.setActive(true)
                    self.ownsAudioSession = true

                    let engine = AVAudioEngine()
                    self.engine = engine
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.channelCount > 0, format.sampleRate > 0 else {
                        throw DeviceCheckFailure.microphoneUnavailable
                    }
                    input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                        var sum: Float = 0
                        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                        let rms = sqrt(sum / Float(buffer.frameLength))
                        let decibels = 20 * log10(max(rms, 0.000001))
                        onLevel(min(1, max(0, (decibels + 60) / 60)))
                    }
                    self.hasTap = true
                    engine.prepare()
                    try engine.start()

                    var front = true
                    if video {
                        self.cameraSession.automaticallyConfiguresApplicationAudioSession = false
                        self.cameraSession.beginConfiguration()
                        do {
                            if self.cameraSession.canSetSessionPreset(.high) { self.cameraSession.sessionPreset = .high }
                            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                                ?? AVCaptureDevice.default(for: .video) else { throw DeviceCheckFailure.cameraUnavailable }
                            let input = try AVCaptureDeviceInput(device: camera)
                            guard self.cameraSession.canAddInput(input) else { throw DeviceCheckFailure.cameraUnavailable }
                            self.cameraSession.addInput(input)
                            self.cameraInput = input
                            front = camera.position == .front
                            self.cameraSession.commitConfiguration()
                        } catch {
                            self.cameraSession.commitConfiguration()
                            throw error
                        }
                        self.cameraSession.startRunning()
                        guard self.cameraSession.isRunning else { throw DeviceCheckFailure.cameraUnavailable }
                    }
                    continuation.resume(returning: front)
                } catch {
                    self.stopOnQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func switchCamera() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard self.cameraSession.isRunning, let previous = self.cameraInput else {
                        throw DeviceCheckFailure.cameraUnavailable
                    }
                    let position: AVCaptureDevice.Position = previous.device.position == .front ? .back : .front
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                        throw DeviceCheckFailure.cameraUnavailable
                    }
                    let replacement = try AVCaptureDeviceInput(device: camera)
                    self.cameraSession.beginConfiguration()
                    self.cameraSession.removeInput(previous)
                    guard self.cameraSession.canAddInput(replacement) else {
                        if self.cameraSession.canAddInput(previous) { self.cameraSession.addInput(previous) }
                        self.cameraSession.commitConfiguration()
                        throw DeviceCheckFailure.cameraUnavailable
                    }
                    self.cameraSession.addInput(replacement)
                    self.cameraInput = replacement
                    self.cameraSession.commitConfiguration()
                    continuation.resume(returning: position == .front)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopOnQueue()
                continuation.resume()
            }
        }
    }

    private func stopOnQueue() {
        if cameraSession.isRunning { cameraSession.stopRunning() }
        cameraSession.beginConfiguration()
        for input in cameraSession.inputs { cameraSession.removeInput(input) }
        cameraSession.commitConfiguration()
        cameraInput = nil
        if hasTap { engine?.inputNode.removeTap(onBus: 0) }
        hasTap = false
        engine?.stop()
        engine?.reset()
        engine = nil
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
        if let previousAudioSettings {
            // The local microphone test must not leave the feed in record-only mode.
            try? AVAudioSession.sharedInstance().setCategory(previousAudioSettings.0,
                mode: previousAudioSettings.1, options: previousAudioSettings.2)
            self.previousAudioSettings = nil
        }
    }
}
#endif
