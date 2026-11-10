import SwiftUI

struct UserAgreementView: View {
    var showsCloseButton = false

    var body: some View {
        LegalPDFView(kind: .userAgreement, showsCloseButton: showsCloseButton) {
            BundledUserAgreementView()
        }
    }
}

private struct BundledUserAgreementView: View {
    private let document = UserAgreementDocument.bundled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let document {
                    agreementHeader(document)
                    Text(verbatim: document.notice)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(document.sections) { section in
                        AppCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(verbatim: section.title)
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                Text(verbatim: section.text)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text(verbatim: "App copy · Available offline\nVersion: \(document.documentVersion)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                } else {
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("User Agreement unavailable").font(.headline)
                            Text("The app copy couldn't be loaded. Contact support for a copy of the agreement.")
                                .foregroundStyle(AppTheme.secondaryInk)
                            Link("fltiya.support@gmail.com", destination: URL(string: "mailto:fltiya.support@gmail.com")!)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
                relatedDocuments
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(AppTheme.ink)
    }

    private func agreementHeader(_ document: UserAgreementDocument) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                ArcadeSticker(kind: .privacy, size: 64)
                Text(verbatim: document.title)
                    .font(.title.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: document.statusText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTACT")
                        .font(.caption.weight(.bold)).tracking(1.4)
                        .foregroundStyle(AppTheme.accent)
                    Text(verbatim: document.contact)
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)
                    if let address = URL(string: "mailto:\(document.contact)") {
                        Link("Email support", destination: address)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var relatedDocuments: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    SocialActionLabel(title: "Privacy Policy", symbol: "chevron.right")
                }
                Divider().overlay(AppTheme.border)
                Link("Apple Standard EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .frame(minHeight: 44, alignment: .leading)
                Link("Apple purchase refund help", destination: URL(string: "https://support.apple.com/118223")!)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack { UserAgreementView() }.tint(AppTheme.accent)
}
