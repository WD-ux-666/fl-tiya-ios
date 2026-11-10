import SwiftUI
import UIKit

@MainActor
struct CallScreen: View {
    let coordinator: CallCoordinator
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let call = coordinator.call {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text(call.peerDisplayName).font(.title.bold())
                        Text(status(for: call)).font(.headline).foregroundStyle(.white.opacity(0.75))
                    }
                    .multilineTextAlignment(.center).padding(.top, 24)
                    stage(for: call)
                    if let error = coordinator.media.errorMessage {
                        Text(error).font(.footnote).multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if coordinator.isIncoming {
                        HStack(spacing: 40) {
                            control("Decline", symbol: "phone.down.fill", color: .red) {
                                Task { await coordinator.reject() }
                            }
                            control("Accept", symbol: call.kind == .video ? "video.fill" : "phone.fill", color: .green) {
                                Task { await coordinator.accept() }
                            }.disabled(coordinator.isWorking)
                        }
                    } else {
                        if call.status == .accepted {
                            mediaControls(video: call.kind == .video)
                        }
                        control(call.status == .ringing ? "Cancel" : "End call", symbol: "phone.down.fill", color: .red) {
                            Task { await coordinator.finish() }
                        }
                    }
                    Text("Keep TIYA open during this call.")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                        .padding(.bottom, 12)
                }
                .padding(24).foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .interactiveDismissDisabled()
        .alert("Call", isPresented: Binding(get: { coordinator.errorMessage != nil }, set: { if !$0 { coordinator.errorMessage = nil } })) {
            Button("OK", role: .cancel) { coordinator.errorMessage = nil }
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
            }
        } message: { Text(coordinator.errorMessage ?? "") }
    }

    @ViewBuilder
    private func stage(for call: FriendCall) -> some View {
        if call.kind == .video, call.status == .accepted, let media = coordinator.media as? LiveCallMedia {
            ZStack(alignment: .topTrailing) {
                LiveCallVideoView(room: media.room)
                LiveCallVideoView(room: media.room, isLocal: true)
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16)).padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: call.kind == .video ? "video.fill" : "person.crop.circle.fill")
                    .font(.system(size: 94)).foregroundStyle(AppTheme.accentSoft)
                if coordinator.isConnecting { ProgressView().tint(.white) }
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mediaControls(video: Bool) -> some View {
        HStack(alignment: .top, spacing: 20) {
            control(coordinator.media.isMicrophoneEnabled ? "Mute" : "Unmute",
                    symbol: coordinator.media.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill") {
                Task { await coordinator.media.toggleMicrophone() }
            }
            control("Speaker", symbol: coordinator.media.isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.fill") {
                coordinator.media.toggleSpeaker()
            }
            if video {
                control("Camera", symbol: coordinator.media.isCameraEnabled ? "video.fill" : "video.slash.fill") {
                    Task { await coordinator.media.toggleCamera() }
                }
                control("Flip", symbol: "arrow.triangle.2.circlepath.camera") {
                    Task { await coordinator.media.switchCamera() }
                }.disabled(!coordinator.media.isCameraEnabled)
            }
        }
        .disabled(!coordinator.media.isConnected || coordinator.isConnecting)
    }

    private func control(_ title: String, symbol: String, color: Color = .white.opacity(0.15), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3)
                    .frame(width: 58, height: 58).background(color, in: Circle())
                Text(title).font(.caption)
            }
        }
        .buttonStyle(.plain).accessibilityLabel(title)
    }

    private func status(for call: FriendCall) -> String {
        if coordinator.isIncoming { return call.kind == .video ? "Incoming video call" : "Incoming voice call" }
        if call.status == .ringing { return "Calling…" }
        if coordinator.isConnecting { return "Connecting…" }
        return coordinator.media.isConnected ? "Connected to call" : "Waiting for connection…"
    }
}
