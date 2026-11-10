#if DEBUG
import SwiftUI

@MainActor
struct DeviceTestContactView: View {
    let ownerID: UUID
    @Environment(\.socialRepository) private var repository
    @Environment(\.callCoordinator) private var calls
    @State private var model = DeviceCheckModel()
    @State private var selectedTest: DeviceCheckMode?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                GameHeroHeader(eyebrow: "LOCAL HARDWARE CHECK", title: "Check your setup.",
                    subtitle: "Local only · Development tool", symbol: "iphone")
                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("This is a local device check, not another player or a real friend connection.")
                        Text("No remote call. Nothing sent or recorded.")
                            .fontWeight(.semibold)
                        Text("Test voice opens your microphone and shows its live input level. Test video also opens your own camera preview.")
                    }.font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { testButtons }
                    VStack(spacing: 12) { testButtons }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.onAccent)
                .disabled(repository?.currentUserID != ownerID || calls?.call != nil || model.isStopping)
                if calls?.call != nil {
                    Text("End your current call before starting a device test.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
                Text("No friend request, message, call history or friend count is created by this tool.")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
            }.padding(24)
        }
        .background { AppBackdrop() }
        .navigationTitle("Device test friend")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedTest) { mode in
            DeviceCheckView(mode: mode, ownerID: ownerID, model: model) {
                repository?.currentUserID == ownerID && calls?.call == nil
            }
        }
        .onChange(of: repository?.currentUserID) { _, userID in if userID != ownerID { stopTest() } }
        .onChange(of: calls?.call?.id) { _, callID in if callID != nil { stopTest() } }
        .onDisappear {
            if selectedTest == nil { stopTest() }
        }
    }

    private var testButtons: some View {
        Group {
            Button { selectedTest = .voice } label: {
                SocialActionLabel(title: "Test voice", symbol: "mic.fill")
            }
            Button { selectedTest = .video } label: {
                SocialActionLabel(title: "Test video", symbol: "video.fill")
            }
        }
    }

    private func stopTest() {
        model.invalidate()
        selectedTest = nil
        Task { await model.stop() }
    }
}
#endif
