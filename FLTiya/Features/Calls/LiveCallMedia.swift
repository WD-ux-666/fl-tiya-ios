import AVFoundation
import LiveKit
import Observation
import SwiftUI

/// Owns media for one foreground call. Call authorization and lifecycle remain
/// in CallCoordinator; LiveKit credentials are issued only by the backend.
@MainActor
@Observable
final class LiveCallMedia: NSObject, CallMediaSession, RoomDelegate {
    private(set) var room = Room()
    private(set) var isConnected = false
    private(set) var isMicrophoneEnabled = false
    private(set) var isCameraEnabled = false
    private(set) var isSpeakerEnabled = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var allowsCamera = false
    @ObservationIgnored private var isUpdatingControls = false
    @ObservationIgnored private var ownedTracks: [Track] = []
    @ObservationIgnored private var isMediaReady = false

    func connect(url: String, token: String, video: Bool) async throws {
        // A cancelled caller must not replace a newer session's media.
        try Task.checkCancellation()
        guard let endpoint = URL(string: url), endpoint.scheme == "wss",
              endpoint.host != nil, !token.isEmpty else {
            throw CallMediaFailure.invalidConnection
        }

        let request = UUID()
        generation = request
        let previousRoom = room
        let previousTracks = ownedTracks
        ownedTracks = []
        previousRoom.remove(delegate: self)
        let callRoom = Room(delegate: self)
        room = callRoom
        isConnected = false
        isMicrophoneEnabled = false
        isCameraEnabled = false
        isSpeakerEnabled = video
        allowsCamera = video
        isUpdatingControls = false
        isMediaReady = false
        errorMessage = nil

        await Self.tearDown(previousRoom, tracks: previousTracks)
        var microphoneTrack: LocalAudioTrack?
        var cameraTrack: LocalVideoTrack?
        do {
            try checkCurrent(request, room: callRoom)
            try await Self.requirePermission(for: .audio)
            try checkCurrent(request, room: callRoom)
            if video {
                try await Self.requirePermission(for: .video)
                try checkCurrent(request, room: callRoom)
            }

            AudioManager.shared.isSpeakerOutputPreferred = video
            // Capture is explicitly enabled only after a successful, still
            // authorized connection. Voice calls never publish a camera track.
            try await callRoom.connect(
                url: url,
                token: token,
                connectOptions: ConnectOptions(enableMicrophone: false)
            )
            try checkCurrent(request, room: callRoom)
            // Retain tracks before publishing so a cancelled or failed publish
            // can stop capture even before a TrackPublication exists.
            let microphone = await LocalAudioTrack.createTrack()
            microphoneTrack = microphone
            try checkCurrent(request, room: callRoom)
            ownedTracks.append(microphone)
            try await callRoom.localParticipant.publish(audioTrack: microphone)
            try checkCurrent(request, room: callRoom)
            isMicrophoneEnabled = true
            if video {
                let camera = await LocalVideoTrack.createCameraTrack()
                cameraTrack = camera
                try checkCurrent(request, room: callRoom)
                ownedTracks.append(camera)
                try await callRoom.localParticipant.publish(videoTrack: camera)
                try checkCurrent(request, room: callRoom)
                isCameraEnabled = true
            }
            isMediaReady = true
            isConnected = callRoom.connectionState == .connected
        } catch {
            // A superseded operation may clean up only its own Room, never the
            // replacement Room created by a subsequent call.
            let createdTracks: [Track?] = [microphoneTrack, cameraTrack]
            await Self.tearDown(callRoom, tracks: createdTracks.compactMap { $0 })
            if generation == request, room === callRoom {
                isConnected = false
                isMicrophoneEnabled = false
                isCameraEnabled = false
                isMediaReady = false
                ownedTracks = []
                if !(error is CancellationError) {
                    errorMessage = (error as? CallMediaFailure)?.errorDescription
                        ?? "Couldn't connect to the call. Please try again."
                }
            }
            throw error
        }
    }

    func disconnect() async {
        generation = UUID()
        let previousRoom = room
        let previousTracks = ownedTracks
        ownedTracks = []
        previousRoom.remove(delegate: self)
        // Drop the visible media immediately while SDK teardown finishes.
        room = Room()
        isConnected = false
        isMicrophoneEnabled = false
        isCameraEnabled = false
        isSpeakerEnabled = false
        allowsCamera = false
        isUpdatingControls = false
        isMediaReady = false
        AudioManager.shared.isSpeakerOutputPreferred = false
        // Room.disconnect stops and unpublishes all local tracks, even if a
        // pending microphone/camera operation failed or was cancelled.
        await Self.tearDown(previousRoom, tracks: previousTracks)
    }

    func toggleMicrophone() async {
        guard isConnected, !isUpdatingControls else { return }
        let request = generation
        let callRoom = room
        let enabled = !isMicrophoneEnabled
        isUpdatingControls = true
        defer { if generation == request { isUpdatingControls = false } }
        do {
            if enabled {
                try await Self.requirePermission(for: .audio)
                try checkCurrent(request, room: callRoom)
            }
            try await callRoom.localParticipant.setMicrophone(enabled: enabled)
            try checkCurrent(request, room: callRoom)
            isMicrophoneEnabled = enabled
            errorMessage = nil
        } catch {
            await handleControlFailure(error, request: request, room: callRoom,
                                       message: "Couldn't change the microphone. Please try again.")
        }
    }

    func toggleCamera() async {
        guard isConnected, allowsCamera, !isUpdatingControls else { return }
        let request = generation
        let callRoom = room
        let enabled = !isCameraEnabled
        isUpdatingControls = true
        defer { if generation == request { isUpdatingControls = false } }
        do {
            if enabled {
                try await Self.requirePermission(for: .video)
                try checkCurrent(request, room: callRoom)
            }
            try await callRoom.localParticipant.setCamera(enabled: enabled)
            try checkCurrent(request, room: callRoom)
            isCameraEnabled = enabled
            errorMessage = nil
        } catch {
            await handleControlFailure(error, request: request, room: callRoom,
                                       message: "Couldn't change the camera. Please try again.")
        }
    }

    func toggleSpeaker() {
        guard isConnected else { return }
        isSpeakerEnabled.toggle()
        // Bluetooth and headphones retain their normal system routing; this
        // preference switches only the built-in receiver/speaker route.
        AudioManager.shared.isSpeakerOutputPreferred = isSpeakerEnabled
    }

    func switchCamera() async {
        guard isConnected, allowsCamera, isCameraEnabled, !isUpdatingControls,
              let track = room.localParticipant.videoTracks
                .first(where: { $0.source == .camera })?.track as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer else { return }
        let request = generation
        let callRoom = room
        isUpdatingControls = true
        defer { if generation == request { isUpdatingControls = false } }
        do {
            guard try await CameraCapturer.canSwitchPosition() else {
                throw CallMediaFailure.cameraUnavailable
            }
            try checkCurrent(request, room: callRoom)
            try await capturer.switchCameraPosition()
            try checkCurrent(request, room: callRoom)
            errorMessage = nil
        } catch {
            await handleControlFailure(error, request: request, room: callRoom,
                                       message: "Couldn't switch cameras. Please try again.")
        }
    }

    // SDK delegate callbacks arrive on an internal queue. Only UI state crosses
    // to the main actor, and retired Rooms cannot update the current call.
    nonisolated func room(_ room: Room, didUpdateConnectionState state: ConnectionState,
                          from oldState: ConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, self.room === room else { return }
            self.isConnected = state == .connected && self.isMediaReady
            if state == .disconnected {
                self.isMediaReady = false
                self.isMicrophoneEnabled = false
                self.isCameraEnabled = false
                if oldState == .connected || oldState == .reconnecting {
                    self.errorMessage = "The call disconnected. Please try again."
                }
            }
        }
    }

    private func checkCurrent(_ request: UUID, room: Room) throws {
        try Task.checkCancellation()
        guard generation == request, self.room === room else {
            throw CancellationError()
        }
    }

    private func handleControlFailure(_ error: Error, request: UUID, room: Room,
                                      message: String) async {
        guard generation == request, self.room === room, !Task.isCancelled else {
            await Self.tearDown(room)
            return
        }
        errorMessage = (error as? CallMediaFailure)?.errorDescription ?? message
    }

    private static func tearDown(_ room: Room, tracks: [Track] = []) async {
        // Logout can cancel the owning SwiftUI task. Use an awaited cleanup
        // task with its own cancellation state so SDK serial runners still
        // execute device stop and disconnect in that case.
        await Task { @MainActor in
            await stopCapture(tracks: tracks, in: room)
            await room.disconnect()
        }.value
    }

    private static func stopCapture(tracks owned: [Track] = [], in room: Room) async {
        // Stop device capture before waiting for any network leave message.
        let published = room.localParticipant.trackPublications.values.compactMap(\.track)
        var stopped = Set<ObjectIdentifier>()
        for track in owned + published {
            guard stopped.insert(ObjectIdentifier(track)).inserted else { continue }
            try? await track.stop()
        }
    }

    private static func requirePermission(for mediaType: AVMediaType) async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            granted = false
        }
        guard granted else {
            throw mediaType == .video ? CallMediaFailure.cameraPermission : CallMediaFailure.microphonePermission
        }
    }
}

private enum CallMediaFailure: LocalizedError {
    case invalidConnection
    case microphonePermission
    case cameraPermission
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConnection:
            return "Calling isn't configured correctly. Please try again later."
        case .microphonePermission:
            return "Allow microphone access in Settings to join a call."
        case .cameraPermission:
            return "Allow camera access in Settings to join a video call."
        case .cameraUnavailable:
            return "Another camera isn't available on this device."
        }
    }
}

/// Uses the video renderer included in the core SDK; no extra UI SDK is needed.
struct LiveCallVideoView: View {
    @ObservedObject var room: Room
    var isLocal = false

    var body: some View {
        Group {
            if let track = cameraTrack {
                SwiftUIVideoView(track, layoutMode: .fill,
                                 mirrorMode: isLocal ? .auto : .off)
            } else {
                ZStack {
                    Color.black
                    Image(systemName: "video.slash.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.75))
                        .accessibilityLabel(isLocal ? "Your camera is off" : "The other camera is off")
                }
            }
        }
        .clipped()
    }

    private var cameraTrack: VideoTrack? {
        let publications = isLocal
            ? room.localParticipant.videoTracks
            : room.remoteParticipants.values.flatMap { $0.videoTracks }
        return publications.first(where: { $0.source == .camera && !$0.isMuted })?.track as? VideoTrack
    }
}
