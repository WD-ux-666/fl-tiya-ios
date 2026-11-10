import SwiftUI

@MainActor
struct ProfileView: View {
    let session: SessionStore
    @Environment(\.socialRepository) private var repository
    @Environment(\.paymentStore) private var payments
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var profile: PlayerProfile?
    @State private var cards: [PlayerGameCard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var editor: ProfileSheet?

    private var displayName: String {
        if let profile { return profile.displayName }
        let name = session.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "Your profile"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                VStack(alignment: .leading, spacing: 24) {
                    SocialLoadFeedback(isLoading: isLoading, errorMessage: errorMessage) { Task { await load() } }
                    if repository != nil {
                        gameCards
                    }
                    sparks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background { SocialThemeBackdrop(theme: .profile) }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: repository?.currentUserID) { await load() }
        .refreshable {
            await load()
            await payments?.refreshAndRetry()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { sheet in
            NavigationStack {
                switch sheet {
                case .profile(let profile): ProfileEditorView(profile: profile)
                case .gameCards: GameCardEditorView(cards: cards)
                }
            }
            .tint(AppTheme.accent)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(session: session)
                } label: {
                    GameGlyph(symbol: "gearshape", size: 23)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The locker artwork now fills the page edge and fades into the
            // same midnight background, with no inset image or enclosing card.
            Color.clear.frame(height: dynamicTypeSize.isAccessibilitySize ? 100 : 150)
                .accessibilityHidden(true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        identityAvatar
                        identityDetails
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        identityAvatar
                        identityDetails
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 20)

            if let bio = profile?.bio.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(.subheadline).lineSpacing(3)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            if let profile, repository != nil {
                Button { editor = .profile(profile) } label: {
                    HStack(spacing: 10) {
                        GameGlyph(symbol: "square.and.pencil", size: 18)
                        Text("Edit profile").font(.subheadline.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 44)
                }
                .foregroundStyle(AppTheme.onAccent)
                .buttonStyle(.borderedProminent).tint(SocialTheme.profile.tint).disabled(isLoading)
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12).padding(.bottom, 18)
        .background(alignment: .top) {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Image("SocialProfileArtwork")
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: 300, alignment: .topTrailing)
                        .clipped()
                    LinearGradient(stops: [
                        .init(color: AppTheme.background.opacity(0.06), location: 0),
                        .init(color: AppTheme.background.opacity(0.35), location: 0.28),
                        .init(color: AppTheme.background.opacity(0.92), location: 0.72),
                        .init(color: AppTheme.background, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: max(300, geometry.size.height))
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var identityAvatar: some View {
        if let profile {
            PlayerAvatarView(profile: profile, size: 76)
                .accessibilityHidden(true)
        } else {
            SocialArtworkBadge(theme: .profile, size: 76)
                .accessibilityHidden(true)
        }
    }

    private var identityDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayName)
                .font(.system(.title, design: .rounded, weight: .black))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let profile {
                Text("@\(profile.handle)")
                    .font(.system(.subheadline, design: .monospaced)).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Handle @\(profile.handle)")
            }
            if !cards.isEmpty {
                HStack(spacing: 7) {
                    GameGlyph(symbol: "gamecontroller.fill", size: 14)
                    Text("\(cards.count) \(cards.count == 1 ? "game" : "games") shared")
                        .font(.caption.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var gameCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("My games")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !cards.isEmpty {
                    Button { editor = .gameCards } label: {
                        Text("Manage").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                    .foregroundStyle(SocialTheme.profile.tint)
                    .accessibilityLabel("Manage game cards")
                    .disabled(isLoading || errorMessage != nil)
                }
            }
            if cards.isEmpty {
                Button { editor = .gameCards } label: {
                    SocialThemePanel(theme: .profile) {
                        HStack(spacing: 14) {
                            SocialArtworkBadge(theme: .profile, size: 44)
                            Text("Add game").font(.headline).foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            GameGlyph(symbol: "plus", size: 22).foregroundStyle(SocialTheme.profile.tint)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add your first game card")
                .disabled(isLoading || errorMessage != nil)
            } else {
                PlayerGameCardsSection(cards: cards, showsTitle: false, onCardsChanged: { await load() })
            }
        }
    }

    private func load() async {
        guard let repository, let userID = repository.currentUserID else {
            loadID = UUID()
            isLoading = false
            profile = nil
            cards = []
            return
        }
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        defer { if loadID == id { isLoading = false } }
        do {
            let loadedProfile = try await repository.profile(id: userID)
            let loadedCards = try await repository.gameCards(userID: userID)
            guard loadID == id, !Task.isCancelled, repository.currentUserID == userID else { return }
            profile = loadedProfile
            cards = loadedCards
        } catch {
            guard loadID == id, !Task.isCancelled, repository.currentUserID == userID else { return }
            profile = nil
            cards = []
            errorMessage = "We couldn't load your profile. Please try again."
        }
    }

    private enum ProfileSheet: Identifiable {
        case profile(PlayerProfile)
        case gameCards
        var id: String {
            switch self {
            case .profile: "profile"
            case .gameCards: "gameCards"
            }
        }
    }

    private var walletCaption: String {
        guard payments?.wallet != nil else { return "Balance unavailable" }
        if payments?.isLocalStoreKitTesting == true { return "Local test balance" }
        return payments?.environment == .sandbox ? "Sandbox balance" : "Available balance"
    }

    private var sparks: some View {
        NavigationLink {
            SparksView()
        } label: {
            SocialThemePanel(theme: .profile) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        ArcadeSticker(kind: .sparks, size: 48)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sparks wallet").font(.headline).foregroundStyle(AppTheme.ink)
                            Text(walletCaption)
                                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        GameGlyph(symbol: "chevron.right", size: 18)
                            .foregroundStyle(AppTheme.accent)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(payments?.wallet?.sparks.formatted() ?? "—")
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(payments?.wallet.map { "\($0.sparks.formatted()) Sparks" } ?? "Balance unavailable")
                        Text("SPARKS")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .tracking(1.5).foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open your Sparks wallet and available packs")
    }
}

#Preview {
    NavigationStack {
        ProfileView(session: SessionStore())
    }
    .tint(AppTheme.accent)
}
