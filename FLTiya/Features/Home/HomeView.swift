import SwiftUI

@MainActor
struct HomeView: View {
    var isSelected = true
    var showsImportedPublisherCredits = false

    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.callCoordinator) private var calls
    @State private var model = ClipFeedModel()
    @State private var scrollClipID: UUID?
    @State private var selectedClipID: UUID?
    @State private var isVisible = false
    @State private var isMuted = true
    @State private var reportPresentation: ReportPresentation?
    @State private var loadedUnblockRevision = 0

    var body: some View {
        let clips = visibleClips
        GeometryReader { geometry in
            ZStack {
                Color.black
                feed(clips: clips, size: geometry.size)
            }
            // ScrollView may draw scrolling content into inherited safe areas.
            // Clip the measured viewport, not only each page's own contents.
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(alignment: .top) { header }
        }
        .background(Color.black)
        .contentReportSheet(item: $reportPresentation, repository: repository)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: loadIdentity) {
            guard isSelected, !Task.isCancelled else { return }
            if model.clips.isEmpty || loadedUnblockRevision != unblockRevision { await reload() }
        }
        .onChange(of: clips.map(\.id)) { previousIDs, ids in
            reconcileSelection(ids: ids, previousIDs: previousIDs)
        }
        .onChange(of: scrollClipID) { _, id in
            // A transient nil during target resolution must not restart page one.
            guard let id, visibleClips.contains(where: { $0.id == id }) else { return }
            selectedClipID = id
        }
        .onChange(of: repository?.currentUserID) { _, _ in
            selectedClipID = nil
            scrollClipID = nil
            reportPresentation = nil
            loadedUnblockRevision = 0
            model.reset()
        }
    }

    private var visibleClips: [ApprovedClip] {
        model.clips.filter { visibility?.isVideoHidden($0.id, authorID: $0.ownerID) != true }
    }

    @ViewBuilder
    private func feed(clips: [ApprovedClip], size: CGSize) -> some View {
        if let repository, !clips.isEmpty {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(clips) { clip in
                        ShortClipPageView(
                            clip: clip,
                            repository: repository,
                            isActive: canPlay && selectedClipID == clip.id,
                            isMuted: $isMuted,
                            importedPublisherCredit: showsImportedPublisherCredits
                                ? ImportedPublisherCredit.forClip(id: clip.id) : nil
                        )
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollClipID)
            .overlay(alignment: .top) {
                if let message = model.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(.horizontal, 20)
                        .padding(.top, 68)
                }
            }
        } else {
            feedState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
        }
    }

    private var canPlay: Bool {
        isSelected && isVisible && reportPresentation == nil && scenePhase == .active && calls?.call == nil
            && repository?.currentUserID != nil
    }

    private var loadIdentity: String {
        "\(repository?.currentUserID?.uuidString ?? "signed-out")|\(isSelected)|\(unblockRevision)"
    }

    private var unblockRevision: Int { visibility?.unblockRevision ?? 0 }

    private var reportTarget: ReportTarget? {
        guard let viewerID = repository?.currentUserID,
              let selectedClipID,
              let clip = visibleClips.first(where: { $0.id == selectedClipID }),
              clip.ownerID != viewerID else { return nil }
        return .video(clip.id)
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image("StickerForYou")
                    .renderingMode(.original).resizable().scaledToFit()
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                Text("For You")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .italic()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Rectangle().fill(AppTheme.accent)
                            .frame(width: 3, height: 11)
                            .rotationEffect(.degrees(22))
                    }
                }
                .padding(.horizontal, 4)
                .accessibilityHidden(true)
            }
            .padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 3)
            .background {
                HomeFeedHeaderPlate().fill(.black.opacity(0.48))
                    .overlay {
                        HomeFeedHeaderPlate().stroke(AppTheme.accent.opacity(0.38), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            if let reportTarget {
                ContentReportButton(target: reportTarget) {
                    guard let reporterID = repository?.currentUserID else { return }
                    reportPresentation = ReportPresentation(target: reportTarget, reporterID: reporterID)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background {
            LinearGradient(colors: [.black.opacity(0.8), .clear],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var feedState: some View {
        VStack(spacing: 16) {
            if model.isLoading {
                ProgressView().tint(.white)
                Text("Loading clips…")
            } else if repository?.currentUserID == nil {
                GameGlyph(symbol: "play.rectangle", size: 36).font(.largeTitle)
                Text("Clips").font(.title3.weight(.bold))
                Text("Sign in to load the live video feed.")
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Image(systemName: model.errorMessage == nil ? "play.rectangle" : "wifi.exclamationmark")
                    .font(.largeTitle)
                Text(model.errorMessage == nil ? "No clips to show" : "Couldn't load clips")
                    .font(.title3.weight(.bold))
                Text(model.errorMessage ?? "Approved clips will appear here when they are available.")
                    .foregroundStyle(.white.opacity(0.7))
                Button("Try again") { Task { await reload() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    private func reload() async {
        guard !Task.isCancelled else { return }
        let previousIDs = visibleClips.map(\.id)
        let actor = repository?.currentUserID
        let requestedRevision = unblockRevision
        await model.load(repository: repository)
        guard !Task.isCancelled, repository?.currentUserID == actor, unblockRevision == requestedRevision else { return }
        if !model.isLoading && model.errorMessage == nil {
            loadedUnblockRevision = requestedRevision
        }
        reconcileSelection(ids: visibleClips.map(\.id), previousIDs: previousIDs)
    }

    private func reconcileSelection(ids: [UUID], previousIDs: [UUID]) {
        if let selectedClipID, ids.contains(selectedClipID) {
            if scrollClipID != selectedClipID { scrollClipID = selectedClipID }
            return
        }
        let nextID: UUID?
        if let selectedClipID, let index = previousIDs.firstIndex(of: selectedClipID) {
            let visibleIDs = Set(ids)
            nextID = previousIDs.dropFirst(index + 1).first(where: visibleIDs.contains)
                ?? previousIDs.prefix(index).reversed().first(where: visibleIDs.contains)
                ?? ids.first
        } else {
            nextID = ids.first
        }
        selectedClipID = nextID
        scrollClipID = nextID
    }
}

private struct HomeFeedHeaderPlate: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 10))
            path.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 8))
            path.closeSubpath()
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
}
