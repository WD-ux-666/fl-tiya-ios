import SwiftUI

@MainActor
struct LoginView: View {
    let session: SessionStore

    private enum LegalDocument: String, Identifiable {
        case privacyPolicy, userAgreement
        var id: Self { self }
    }

    @State private var selectedLegalDocument: LegalDocument?
    #if DEBUG && COMMUNITY_TESTING
    @State private var emailAddress = ""
    @State private var testEmailError: String?
    @FocusState private var isEmailFocused: Bool
    private let testAccounts = CommunityTestAccount.configured
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 54

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LoginStageLayout(
                    width: min(440, max(0, geometry.size.width - 44)),
                    viewportHeight: geometry.size.height,
                    showsDecoration: !dynamicTypeSize.isAccessibilitySize
                ) {
                    LoginArcadeBand(.marquee)
                    welcomePanel
                    LoginArcadeDivider()
                    VStack(spacing: 20) {
                        signInSection
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity)
                        if dynamicTypeSize.isAccessibilitySize {
                            consentFooter
                        }
                    }
                    LoginArcadeBand(.afterglow)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                consentFooter
                    .padding(.horizontal, 22)
                    .background {
                        AppTheme.background.ignoresSafeArea(.container, edges: .bottom)
                    }
            }
        }
        .background { AppBackdrop() }
        .sheet(item: $selectedLegalDocument) { document in
            NavigationStack {
                switch document {
                case .privacyPolicy: PrivacyPolicyView(showsCloseButton: true)
                case .userAgreement: UserAgreementView(showsCloseButton: true)
                }
            }
        }
    }

    private var welcomePanel: some View {
        welcomeArtwork
            .background(AppTheme.surface)
            .clipShape(SocialEditorButtonOutline())
            .overlay {
                SocialEditorButtonOutline()
                    .stroke(
                        LinearGradient(colors: [AppTheme.accent.opacity(0.60), AppTheme.border, AppTheme.violet.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(color: AppTheme.violet.opacity(0.14), radius: 16, x: 0, y: 7)
    }

    private var welcomeArtwork: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAYER CONNECT")
                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(AppTheme.accent)
            Text("TIYA")
                .font(.system(size: wordmarkSize, weight: .black, design: .rounded))
                .tracking(-2)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .accessibilityAddTraits(.isHeader)
            Text("Find your next player.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink.opacity(0.88))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 234, alignment: .bottomLeading)
        .background {
            GeometryReader { geometry in
                Image("LoginArcadeArtwork")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                    .clipped()
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: AppTheme.background.opacity(0.18), location: 0.78),
                            .init(color: AppTheme.background.opacity(0.72), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: AppTheme.background.opacity(0.74), location: 0),
                            .init(color: AppTheme.background.opacity(0.51), location: 0.39),
                            .init(color: AppTheme.background.opacity(dynamicTypeSize.isAccessibilitySize ? 0.68 : 0.08),
                                  location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var signInSection: some View {
        VStack(spacing: 14) {
            #if DEBUG && COMMUNITY_TESTING
            testAccountForm
            #endif

            #if DEBUG && COMMUNITY_TESTING
            if !testAccounts.isEmpty {
                primaryButton("Continue with email", enabled: canContinueWithTestEmail, action: enterTestEmail)
                    .accessibilityHint("Signs in to the selected test account.")
            }
            #else
            primaryButton("One-tap sign in", enabled: canUseOneTap) {
                guard canUseOneTap else { return }
                Task { await session.signInForExperience() }
            }
            .accessibilityHint("Creates an account on this device. Agree to the User Agreement and Privacy Policy to continue.")

            if !session.isExperienceSignInAvailable {
                Text("One-tap sign-in is currently unavailable.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif

            signInFeedback
        }
        .multilineTextAlignment(.center)
    }

    private var accentRule: some View {
        LinearGradient(colors: [AppTheme.accent.opacity(0.56), AppTheme.violet.opacity(0.3), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var consentFooter: some View {
        VStack(spacing: 0) {
            accentRule.frame(maxWidth: 440)
            consentRow
                .frame(maxWidth: 440)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
    }

    private var consentRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                session.setLegalConsent(!session.hasAgreedToLegalDocuments)
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(session.hasAgreedToLegalDocuments ? AppTheme.accent : AppTheme.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(AppTheme.accent.opacity(0.75), lineWidth: 1.5)
                    }
                    .overlay {
                        if session.hasAgreedToLegalDocuments {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(AppTheme.onAccent)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isSigningIn)
            .accessibilityLabel("Agree to the User Agreement and Privacy Policy")
            .accessibilityValue(session.hasAgreedToLegalDocuments ? "Checked" : "Unchecked")
            .accessibilityAddTraits(session.hasAgreedToLegalDocuments ? .isSelected : [])
            .accessibilityIdentifier("legal-consent")

            VStack(alignment: .leading, spacing: 0) {
                Text("I agree to the")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        legalButton("User Agreement", document: .userAgreement)
                        Text("and").font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                            .accessibilityHidden(true)
                        legalButton("Privacy Policy", document: .privacyPolicy)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        legalButton("User Agreement", document: .userAgreement)
                        legalButton("Privacy Policy", document: .privacyPolicy)
                    }
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    private func legalButton(_ title: LocalizedStringKey, document: LegalDocument) -> some View {
        Button {
            selectedLegalDocument = document
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .underline()
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                GameGlyph(symbol: "arrow.right", size: 18)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LoginActionButtonStyle())
        .disabled(!enabled)
    }

    #if !(DEBUG && COMMUNITY_TESTING)
    private var canUseOneTap: Bool {
        session.hasAgreedToLegalDocuments && !session.isSigningIn && session.isExperienceSignInAvailable
    }
    #endif

    @ViewBuilder
    private var signInFeedback: some View {
        if session.isSigningIn {
            HStack(spacing: 8) {
                ProgressView().tint(AppTheme.accent)
                Text("Signing in…")
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryInk)
            .accessibilityElement(children: .combine)
        }

        if let errorMessage = signInErrorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Sign-in error. \(errorMessage)")
        }
    }

    private var signInErrorMessage: String? {
        #if DEBUG && COMMUNITY_TESTING
        testEmailError ?? session.errorMessage
        #else
        session.errorMessage
        #endif
    }

    #if DEBUG && COMMUNITY_TESTING
    private var isTestEmailAvailable: Bool {
        session.isDevelopmentSignInAvailable && !testAccounts.isEmpty
    }

    private var canContinueWithTestEmail: Bool {
        session.hasAgreedToLegalDocuments && !session.isSigningIn && isTestEmailAvailable
            && ExperienceEmailAddress.normalized(emailAddress) != nil
    }

    private var testAccountForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with a test email")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            ForEach(testAccounts) { account in
                Button {
                    testEmailError = nil
                    emailAddress = account.email
                    isEmailFocused = false
                } label: {
                    HStack(spacing: 10) {
                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if CommunityTestAccount.matching(emailAddress, in: testAccounts)?.id == account.id {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .foregroundStyle(AppTheme.accent)
                    .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(session.isSigningIn || !isTestEmailAvailable)
                .accessibilityHint("Fills the email address for this test account.")
            }
            if !testAccounts.isEmpty {
                TextField(text: $emailAddress, prompt: Text("Email address").foregroundStyle(AppTheme.secondaryInk)) {
                    Text("Email address")
                }
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(enterTestEmail)
                .focused($isEmailFocused)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 1))
                .foregroundStyle(AppTheme.ink)
                .privacySensitive()
                .disabled(session.isSigningIn || !isTestEmailAvailable)
                .onChange(of: emailAddress) { _, _ in testEmailError = nil }
            }
            Text(testAccounts.isEmpty
                 ? "Test accounts aren’t set up on this device. Quit Xcode, reopen the project, and run FLTiyaCommunityTesting-Local."
                 : isTestEmailAvailable
                    ? "Select a test account or enter its email. You can switch accounts after signing out."
                    : "Test sign-in is currently unavailable.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }

    private func enterTestEmail() {
        guard canContinueWithTestEmail else { return }
        guard let account = CommunityTestAccount.matching(emailAddress, in: testAccounts) else {
            testEmailError = "Choose one of the configured test accounts to see the test players and activity."
            return
        }
        testEmailError = nil
        isEmailFocused = false
        Task { await session.signInForDevelopment(accessCode: account.accessCode) }
    }
    #endif
}

/// Measures the hero and actions before distributing spare space to the artwork bands.
private struct LoginStageLayout: Layout {
    let width: CGFloat
    let viewportHeight: CGFloat
    let showsDecoration: Bool

    private let margin: CGFloat = 24
    private let minimumGap: CGFloat = 22
    private var contentProposal: ProposedViewSize { ProposedViewSize(width: width, height: nil) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heroHeight = subviews[1].sizeThatFits(contentProposal).height
        let actionHeight = subviews[3].sizeThatFits(contentProposal).height
        return CGSize(width: width, height: max(viewportHeight, heroHeight + actionHeight + minimumGap + margin * 2))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heroHeight = subviews[1].sizeThatFits(contentProposal).height
        let actionHeight = subviews[3].sizeThatFits(contentProposal).height
        let spareHeight = max(0, bounds.height - heroHeight - actionHeight - minimumGap - margin * 2)
        let upperHeight = showsDecoration ? min(78, spareHeight * 0.22) : 0
        let middleExtra = showsDecoration ? min(74, spareHeight * 0.22) : 0
        let lowerHeight = showsDecoration ? spareHeight - upperHeight - middleExtra : 0
        let heights = [upperHeight, heroHeight, minimumGap + middleExtra, actionHeight, lowerHeight]

        var y = bounds.minY + margin
        for (index, height) in heights.enumerated() {
            let isContent = index == 1 || index == 3
            let childProposal = isContent ? contentProposal
                : ProposedViewSize(width: width, height: showsDecoration ? height : 0)
            subviews[index].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: childProposal)
            y += height
        }
    }
}

private struct LoginArcadeBand: View {
    enum Artwork: String {
        case marquee = "LoginArcadeMarquee"
        case afterglow = "LoginArcadeAfterglow"
    }

    let artwork: Artwork

    init(_ artwork: Artwork) {
        self.artwork = artwork
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            if height >= 36, width >= 180 {
                let isMarquee = artwork == .marquee
                Image(artwork.rawValue)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width - 20, height: min(isMarquee ? 72 : 96, height - 8))
                    .opacity(isMarquee ? 0.94 : 0.80)
                    .position(x: width / 2, y: height * (isMarquee ? 0.50 : 0.47))
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LoginArcadeDivider: View {
    var body: some View {
        Canvas { context, size in
            guard size.width >= 180, size.height >= 42 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for side: CGFloat in [-1, 1] {
                let tint = side < 0 ? AppTheme.accent : AppTheme.violet
                let endX = center.x + side * size.width * 0.40
                var track = Path()
                track.move(to: CGPoint(x: endX, y: center.y + 6))
                track.addLine(to: CGPoint(x: center.x + side * 54, y: center.y + 6))
                track.addLine(to: CGPoint(x: center.x + side * 46, y: center.y - 2))
                track.addLine(to: CGPoint(x: center.x + side * 29, y: center.y - 2))
                context.stroke(track, with: .color(tint.opacity(0.34)), lineWidth: 1)
                context.fill(Path(CGRect(x: endX - 2, y: center.y + 4, width: 4, height: 4)),
                             with: .color(tint.opacity(0.46)))
            }

            let tints = [AppTheme.accent, SocialTheme.profile.tint, AppTheme.violet]
            for (index, tint) in tints.enumerated() {
                let x = center.x + CGFloat(index - 1) * 12
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: center.y - 7))
                stripe.addLine(to: CGPoint(x: x + 5, y: center.y - 7))
                stripe.addLine(to: CGPoint(x: x, y: center.y + 7))
                stripe.addLine(to: CGPoint(x: x - 5, y: center.y + 7))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(tint.opacity(0.62)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LoginActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = SocialEditorButtonOutline()
        let highlight = SocialTheme.profile.tint
        return configuration.label
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(isEnabled ? AppTheme.onAccent : AppTheme.secondaryInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .background {
                shape.fill(LinearGradient(
                    colors: isEnabled ? [highlight, Color(red: 1, green: 0.69, blue: 0.33)]
                                      : [AppTheme.surface, AppTheme.surface],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: isEnabled ? AppTheme.violet.opacity(0.72) : .clear, radius: 0,
                        x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            }
            .overlay {
                shape.stroke(isEnabled ? AppTheme.ink.opacity(0.78) : AppTheme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(0..<3) { _ in
                        Rectangle()
                            .fill(isEnabled ? AppTheme.onAccent.opacity(0.55) : AppTheme.secondaryInk.opacity(0.45))
                            .frame(width: 3, height: 5)
                            .rotationEffect(.degrees(28))
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .contentShape(Rectangle())
    }
}

#Preview("Login") {
    LoginView(session: SessionStore())
}
