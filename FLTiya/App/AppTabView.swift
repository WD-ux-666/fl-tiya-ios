import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case games
    case players
    case messages
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .games: "Games"
        case .players: "Players"
        case .messages: "Messages"
        case .profile: "Profile"
        }
    }

    var dockImageName: String {
        switch self {
        case .home: "DockHome"
        case .games: "DockGames"
        case .players: "DockPlayers"
        case .messages: "DockMessages"
        case .profile: "DockProfile"
        }
    }
}

@MainActor
struct AppTabView: View {
    let session: SessionStore
    @State private var selection: AppTab = .home
    @State private var sampleMessages = SampleMessageStore()

    private var sampleAccountID: UUID? {
        guard session.isExperienceSession else { return nil }
        return session.verifiedUserID.flatMap(UUID.init(uuidString:))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack {
                        content(for: tab)
                            .toolbarBackground(AppTheme.background, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                            .toolbarColorScheme(.dark, for: .navigationBar)
                    }
                    // Tab bar visibility must flow from a child to its TabView.
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
                }
            }
            // Reserve real layout height for pushed pages and their input bars.
            navigationDock
        }
        .environment(\.sampleMessages, sampleAccountID == nil ? nil : sampleMessages)
        .task(id: sampleAccountID) {
            if let sampleAccountID, !sampleMessages.isReady(for: sampleAccountID) {
                sampleMessages.load(for: sampleAccountID)
            }
        }
        .background(AppTheme.background)
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var navigationDock: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(tab.dockImageName)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .saturation(selection == tab ? 1 : 0.72)
                            .opacity(selection == tab ? 1 : 0.82)
                            .shadow(color: selection == tab ? AppTheme.accent.opacity(0.22) : .clear,
                                    radius: 7, y: 2)
                            .accessibilityHidden(true)
                        Text(tab.title)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(selection == tab ? AppTheme.accent : AppTheme.secondaryInk)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .top)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(colors: [AppTheme.accent.opacity(0.13),
                                                              AppTheme.surface.opacity(0.7)],
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(AppTheme.background)
        .overlay(alignment: .top) {
            Rectangle().fill(LinearGradient(colors: [.clear, AppTheme.violet.opacity(0.45),
                AppTheme.accent.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView(isSelected: selection == .home, showsImportedPublisherCredits: session.isExperienceSession)
        case .games: GamesView()
        case .players: PlayersView()
        case .messages: MessagesView()
        case .profile: ProfileView(session: session)
        }
    }
}

// Canvas-only navigation preview. Release RootView always enforces authentication.
#Preview("Five-page navigation") {
    AppTabView(session: SessionStore())
        .preferredColorScheme(.dark)
}
