#if DEBUG
import SwiftUI

enum DevelopmentPreviewConfiguration {
    static var opensAutomatically: Bool {
        #if DEVELOPMENT_PREVIEW
        true
        #else
        false
        #endif
    }
}

private struct ExitDevelopmentPreviewKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var exitDevelopmentPreview: (() -> Void)? {
        get { self[ExitDevelopmentPreviewKey.self] }
        set { self[ExitDevelopmentPreviewKey.self] = newValue }
    }
}

@MainActor
struct DevelopmentPreviewView: View {
    let onExit: () -> Void

    // Preview pages never receive the production session or a fake verified user.
    @State private var previewSession = SessionStore(authenticationService: UnavailableAuthenticationService())

    var body: some View {
        AppTabView(session: previewSession)
            .environment(\.exitDevelopmentPreview, onExit)
            .safeAreaInset(edge: .top, spacing: 0) {
                previewBanner
            }
    }

    private var previewBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Development preview", systemImage: "hammer.fill")
                    .font(.caption.weight(.bold))
                Text("No live services")
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.accent)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button(action: onExit) {
                Label("Exit preview", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .accessibilityHint("Returns to the sign-in page.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(AppTheme.accentSoft)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 0.5)
        }
    }
}

#Preview("Development preview") {
    DevelopmentPreviewView(onExit: {})
        .preferredColorScheme(.dark)
}
#endif
