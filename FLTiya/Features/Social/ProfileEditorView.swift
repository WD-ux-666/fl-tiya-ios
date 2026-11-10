import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ProfileEditorView: View {
    let profile: PlayerProfile
    @Environment(\.socialRepository) private var repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var displayName: String
    @State private var bio: String
    @State private var imageSelection: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    @State private var selectedAvatarPreview: UIImage?
    @State private var uploadedAvatarPath: String?
    @State private var isPreparingAvatar = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    init(profile: PlayerProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio)
    }

    private var cleanName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !cleanName.isEmpty && cleanName.unicodeScalars.count <= 80 && bio.unicodeScalars.count <= 500 }
    private var canSave: Bool {
        isValid && !isSaving && !isPreparingAvatar && repository?.currentUserID == profile.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                avatarPicker
                editorField(title: "Display name") {
                    TextField("Your player name", text: $displayName)
                        .textContentType(.nickname)
                        .font(.headline)
                        .accessibilityIdentifier("profile.displayName")
                    fieldFooter("1–80 characters", count: cleanName.unicodeScalars.count, maximum: 80)
                }
                editorField(title: "About you") {
                    TextField("Games and things you enjoy", text: $bio, axis: .vertical)
                        .lineLimit(4...8).font(.body)
                        .accessibilityIdentifier("profile.bio")
                    fieldFooter("About you", count: bio.unicodeScalars.count, maximum: 500, showsCount: true)
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline)
                        .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.saveError")
                }
            }
            .padding(20).padding(.bottom, 28).disabled(isSaving)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { SocialThemeBackdrop(theme: .profile) }
        .safeAreaInset(edge: .top, spacing: 0) { editorToolbar }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isSaving)
        .task(id: imageSelection) { await prepareAvatar() }
        .onDisappear { saveTask?.cancel() }
    }

    private var editorToolbar: some View {
        VStack(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Edit profile").font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
            }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                    .disabled(isSaving).accessibilityIdentifier("profile.cancel")
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Edit profile").font(.headline).foregroundStyle(AppTheme.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    saveTask = Task { await save() }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().tint(AppTheme.onAccent) }
                        Text(isSaving ? "Saving" : "Save")
                    }
                }
                .buttonStyle(SocialEditorButtonStyle(isPrimary: true))
                .disabled(!canSave).accessibilityIdentifier("profile.save")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(AppTheme.background.opacity(0.96))
    }

    private var avatarPicker: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $imageSelection, matching: .images) {
                VStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let selectedAvatarPreview {
                                Image(uiImage: selectedAvatarPreview).resizable().scaledToFill()
                                    .frame(width: 104, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 25))
                            } else {
                                PlayerAvatarView(profile: profile, size: 104)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 25)
                                .strokeBorder(SocialTheme.profile.tint.opacity(0.7), lineWidth: 2)
                        }
                        GameGlyph(symbol: "plus", size: 16).foregroundStyle(AppTheme.onAccent)
                            .frame(width: 30, height: 30)
                            .background(SocialTheme.profile.tint, in: Circle()).offset(x: 6, y: 6)
                    }
                    Text(selectedAvatarData == nil ? "Change avatar" : "Change selected photo")
                        .font(.subheadline.weight(.bold)).foregroundStyle(SocialTheme.profile.tint)
                        .frame(minHeight: 32)
                }
                .padding(.vertical, 16).frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(isPreparingAvatar || isSaving)
            .accessibilityLabel("Choose a profile photo")
            .accessibilityHint("Select a photo to use as your avatar after saving")
            .accessibilityIdentifier("profile.chooseAvatar")
            if isPreparingAvatar {
                ProgressView("Preparing photo…").font(.caption).tint(SocialTheme.profile.tint)
            } else if selectedAvatarData != nil {
                Text("Photo selected · Save to upload").font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func editorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(.caption, design: .monospaced, weight: .heavy))
                .tracking(1.5).foregroundStyle(SocialTheme.profile.tint)
            SocialThemePanel(theme: .profile) {
                VStack(alignment: .leading, spacing: 16, content: content)
                    .foregroundStyle(AppTheme.ink).tint(SocialTheme.profile.tint)
            }
        }
    }

    private func fieldFooter(_ title: String, count: Int, maximum: Int, showsCount: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
            Text(showsCount ? "\(count)/\(maximum) characters" : title).font(.caption)
                .foregroundStyle(count > maximum ? Color.red : AppTheme.secondaryInk)
        }
    }

    private func prepareAvatar() async {
        guard let imageSelection else { return }
        isPreparingAvatar = true
        errorMessage = nil
        defer { isPreparingAvatar = false }
        do {
            guard let data = try await imageSelection.loadTransferable(type: Data.self) else {
                throw AvatarMediaFailure.invalidImage
            }
            try Task.checkCancellation()
            let normalized = try await AvatarImageProcessor.shared.normalizedJPEG(from: data)
            guard !Task.isCancelled, self.imageSelection == imageSelection,
                  repository?.currentUserID == profile.id,
                  let preview = UIImage(data: normalized) else { return }
            selectedAvatarData = normalized
            selectedAvatarPreview = preview
            uploadedAvatarPath = nil
        } catch {
            guard !Task.isCancelled, self.imageSelection == imageSelection else { return }
            errorMessage = "We couldn't open that photo. Choose a still image smaller than 25 MB."
        }
    }

    private func save() async {
        guard let repository, canSave else { return }
        let actor = profile.id
        let name = cleanName
        let about = bio
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let selectedAvatarData {
                if uploadedAvatarPath == nil {
                    let path = try await repository.uploadAvatar(selectedAvatarData)
                    guard !Task.isCancelled, repository.currentUserID == actor else { return }
                    // Reuse an immutable upload when a metadata save needs retrying.
                    uploadedAvatarPath = path
                }
                guard let uploadedAvatarPath else { throw AvatarMediaFailure.invalidPath }
                try Task.checkCancellation()
                guard repository.currentUserID == actor else { return }
                try await repository.updateProfile(displayName: name, bio: about, avatarPath: uploadedAvatarPath)
            } else {
                try Task.checkCancellation()
                guard repository.currentUserID == actor else { return }
                try await repository.updateProfile(displayName: name, bio: about)
            }
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            dismiss()
        } catch {
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "We couldn't save your profile. Your changes are still here; please try again."
        }
    }
}
