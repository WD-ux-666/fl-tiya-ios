import SwiftUI

@MainActor
struct SettingsView: View {
    let session: SessionStore
    @State private var isConfirmingExperienceSignOut = false
    @State private var isConfirmingDeletion = false

    #if DEBUG
    @Environment(\.exitDevelopmentPreview) private var exitDevelopmentPreview
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GameHeroHeader(eyebrow: "CONTROL CENTER", title: "Your setup.",
                    subtitle: "Your account, privacy and support.", symbol: "gearshape.fill", sticker: .settings)
                safety
                information
                account
                Text("TIYA  /  \(AppVersion.display)")
                    .font(.caption2.weight(.bold)).tracking(2).foregroundStyle(AppTheme.secondaryInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Settings")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out of this device account?", isPresented: $isConfirmingExperienceSignOut) {
            Button("Sign Out", role: .destructive) { session.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out removes access to this device account. The next one-tap sign-in creates a new account. Your existing account data won’t be deleted.")
        }
        .confirmationDialog("Permanently delete this account?", isPresented: $isConfirmingDeletion,
                            titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await session.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionWarning)
        }
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsHeading("Safety", sticker: .players)

            AppCard {
                NavigationLink {
                    BlockedPlayersView()
                } label: {
                    SettingsRow(sticker: .players, title: "Blacklist", detail: "Manage blocked players")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsHeading("Information", sticker: .privacy)

            AppCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        UserAgreementView()
                    } label: {
                        SettingsRow(sticker: .privacy, title: "User Agreement", detail: "Community rules and terms")
                    }

                    Divider().overlay(AppTheme.border)

                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        SettingsRow(sticker: .privacy, title: "Privacy Policy", detail: "How we handle your data")
                    }

                    Divider().overlay(AppTheme.border)

                    NavigationLink {
                        SupportInformationView()
                    } label: {
                        SettingsRow(sticker: .support, title: "Support", detail: "Get in touch")
                    }

                }
                .buttonStyle(.plain)
            }
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsHeading("Account", sticker: .avatar)

            AppCard {
                #if DEBUG
                if let exitDevelopmentPreview {
                    Button(action: exitDevelopmentPreview) {
                        accountActionLabel("Exit preview")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                } else {
                    accountActions
                }
                #else
                accountActions
                #endif
            }
        }
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.isExperienceSession {
                HStack(spacing: 10) {
                    GameGlyph(symbol: "iphone", size: 24).foregroundStyle(AppTheme.violet)
                    Text("Device account").font(.headline).foregroundStyle(AppTheme.ink)
                }
                Text("Saved securely on this device. Signing out removes access to this account. Purchases require a recoverable account.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(AppTheme.border)
            }

            signOutButton

            if session.isAuthenticated {
                Divider().overlay(AppTheme.border)
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    SocialActionLabel(title: "Delete Account", symbol: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                Text("Permanently removes your account and its uploaded content.")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.isDeletingAccount {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Deleting account…")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity)
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(session.isDeletingAccount || session.isSigningOut)
    }

    private var deletionWarning: String {
        let removal = "Your profile, avatar, game cards, friendships, messages, comments, likes and uploaded videos will be permanently removed. This can’t be undone. Records that must be retained for payment or security purposes are kept separately."
        if session.isDevelopmentSession {
            return removal + " This is a development account: its uploaded test clips will also disappear, and its test access code will be permanently retired."
        }
        return removal
    }

    private func settingsHeading(_ title: String, sticker: ArcadeStickerKind) -> some View {
        HStack(spacing: 10) {
            ArcadeSticker(kind: sticker, size: 30)
            Text(title).font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            if session.isExperienceSession {
                isConfirmingExperienceSignOut = true
            } else {
                session.signOut()
            }
        } label: {
            accountActionLabel("Sign Out")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }

    private func accountActionLabel(_ title: String) -> some View {
        SocialActionLabel(title: title, symbol: "rectangle.portrait.and.arrow.right")
    }
}

private struct SettingsRow: View {
    let sticker: ArcadeStickerKind
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            ArcadeSticker(kind: sticker, size: 50)
                .frame(width: 52, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            Spacer(minLength: 8)

            GameGlyph(symbol: "chevron.right", size: 16)
                .foregroundStyle(AppTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct SupportInformationView: View {
    var body: some View {
        ScrollView {
            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    ArcadeSticker(kind: .support, size: 84)

                    Text("Support contact")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    Text("Questions about your account, privacy or the community? Contact us by email.")
                        .foregroundStyle(AppTheme.secondaryInk)

                    Link(destination: URL(string: "mailto:fltiya.support@gmail.com")!) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CONTACT")
                                .font(.caption.weight(.bold)).tracking(1.4)
                                .foregroundStyle(AppTheme.accent)
                            Text("fltiya.support@gmail.com")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(16)
                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Email support at fltiya.support@gmail.com")
                    Text("Opens your email app. If no email app is set up, copy the address above.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Support")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum AppVersion {
    static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let version, !version.isEmpty else { return "Not available" }
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView(session: SessionStore())
    }
    .tint(AppTheme.accent)
}
