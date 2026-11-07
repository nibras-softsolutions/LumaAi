import SwiftUI
import PhotosUI

public struct EditProfileView: View {
    @ObservedObject var userPreferences: UserPreferences
    let currentUser: User?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var selectedEmoji: String = "👤"
    @State private var selectedColorHex: String = "#FFC43D"
    @State private var selectedImageData: Data? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showingResetAlert: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false

    private let avatarEmojis: [String] = ["👤", "🧑‍💻", "⚡️", "🌟", "🚀", "🦊", "🦁", "💎", "🦉", "🎨", "💡", "☕️"]
    private let colorOptions: [(name: String, hex: String)] = [
        ("Gold", "#FFC43D"),
        ("Blue", "#2563EB"),
        ("Purple", "#8B5CF6"),
        ("Emerald", "#10B981"),
        ("Rose", "#EC4899"),
        ("Dark", "#1C1917")
    ]

    public init(
        userPreferences: UserPreferences = .shared,
        currentUser: User?,
        onSave: @escaping () -> Void = {}
    ) {
        self.userPreferences = userPreferences
        self.currentUser = currentUser
        self.onSave = onSave

        _displayName = State(initialValue: userPreferences.customDisplayName ?? currentUser?.fullName ?? "")
        _bio = State(initialValue: userPreferences.customBio ?? "Thinking and creating with Luma AI")
        _selectedEmoji = State(initialValue: userPreferences.customAvatarEmoji ?? "👤")
        _selectedColorHex = State(initialValue: userPreferences.customAvatarColorHex ?? "#FFC43D")
        _selectedImageData = State(initialValue: userPreferences.customProfileImageData)
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Avatar Visualizer
                    avatarVisualizer

                    // Emoji Palette
                    emojiPickerSection

                    // Color Palette
                    colorPickerSection

                    // Form Fields
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DISPLAY NAME")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.settingsSectionLabel)

                            TextField("Your Name", text: $displayName)
                                .font(.system(size: 15))
                                .foregroundColor(.settingsPrimaryText)
                                .padding(14)
                                .background(Color.settingsCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.settingsDivider, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("BIO / STATUS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.settingsSectionLabel)

                            TextField("A short bio or headline", text: $bio)
                                .font(.system(size: 15))
                                .foregroundColor(.settingsPrimaryText)
                                .padding(14)
                                .background(Color.settingsCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.settingsDivider, lineWidth: 1)
                                )
                        }
                    }

                    // Reset / Delete Customization
                    if userPreferences.hasCustomProfile {
                        Button(action: {
                            showingResetAlert = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Customization (Reset Profile)")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.lumaError)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(Color.settingsBackground.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.settingsSecondaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        saveProfile()
                    }) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.lumaInversePrimaryText))
                                .frame(width: 48, height: 28)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.lumaInversePrimaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(Color.settingsPrimaryText)
                    .clipShape(Capsule())
                    .disabled(isSaving)
                }
            }
            .confirmationDialog("Reset Profile Customization?", isPresented: $showingResetAlert, titleVisibility: .visible) {
                Button("Delete Customization", role: .destructive) {
                    Task {
                        _ = try? await APIClient.shared.resetUserProfile()
                        await MainActor.run {
                            userPreferences.resetProfileCustomization()
                            selectedImageData = nil
                            selectedEmoji = "👤"
                            selectedColorHex = "#FFC43D"
                            HapticFeedback.light()
                            onSave()
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your custom photo, avatar, name override, and bio, reverting to your original account profile.")
            }
            .alert("Profile Update Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred while updating profile.")
            }
        }
    }

    private var avatarVisualizer: some View {
        VStack(spacing: 12) {
            ZStack {
                if let data = selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.orbixCardBorder, lineWidth: 2))
                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                } else {
                    Circle()
                        .fill(Color(hex: selectedColorHex).opacity(0.18))
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: selectedColorHex), lineWidth: 2)
                        )
                        .overlay(
                            Text(selectedEmoji)
                                .font(.system(size: 42))
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                }
            }

            // PhotosPicker Button & Options
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text(selectedImageData != nil ? "Change Photo" : "Upload Photo")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.settingsPrimaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.settingsCard)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.settingsDivider, lineWidth: 1)
                    )
                }

                if selectedImageData != nil {
                    Button(action: {
                        HapticFeedback.light()
                        selectedImageData = nil
                        selectedPhotoItem = nil
                    }) {
                        Text("Use Character")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.settingsSecondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.settingsCard.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
            }

            Text(selectedImageData != nil ? "Custom photo will be used across Chat and Settings" : "Choose a photo or select an avatar character below")
                .font(.system(size: 12))
                .foregroundColor(.settingsSecondaryText)
        }
        .padding(.top, 8)
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        if let img = UIImage(data: data) {
                            let maxDim: CGFloat = 512
                            let size = img.size
                            let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
                            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                            let renderer = UIGraphicsImageRenderer(size: newSize)
                            let scaledImage = renderer.image { _ in
                                img.draw(in: CGRect(origin: .zero, size: newSize))
                            }
                            if let compressed = scaledImage.jpegData(compressionQuality: 0.8) {
                                self.selectedImageData = compressed
                            } else {
                                self.selectedImageData = data
                            }
                        } else {
                            self.selectedImageData = data
                        }
                    }
                }
            }
        }
    }

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVATAR ICON")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.settingsSectionLabel)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(avatarEmojis, id: \.self) { emoji in
                    let isSelected = selectedEmoji == emoji && selectedImageData == nil
                    Button(action: {
                        HapticFeedback.selection()
                        selectedEmoji = emoji
                        selectedImageData = nil
                    }) {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .background(isSelected ? Color.settingsCard : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? Color.settingsPrimaryText : Color.clear, lineWidth: 1.5)
                            )
                    }
                }
            }
            .padding(12)
            .background(Color.settingsCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.settingsDivider, lineWidth: 1)
            )
        }
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACCENT COLOR")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.settingsSectionLabel)

            HStack(spacing: 14) {
                ForEach(colorOptions, id: \.hex) { item in
                    let isSelected = selectedColorHex == item.hex
                    Button(action: {
                        HapticFeedback.selection()
                        selectedColorHex = item.hex
                    }) {
                        Circle()
                            .fill(Color(hex: item.hex))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle()
                                    .stroke(Color.settingsCard, lineWidth: isSelected ? 2.5 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.settingsPrimaryText, lineWidth: isSelected ? 1.5 : 0)
                            )
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(Color.settingsCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.settingsDivider, lineWidth: 1)
            )
        }
    }

    private func saveProfile() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)

        let previousImageData = userPreferences.customProfileImageData
        let photoChanged = (selectedImageData != previousImageData)

        Task {
            do {
                try? await APIClient.shared.ensureSession()
                var updatedUser: User? = nil

                // 1. Upload or delete photo if changed
                if photoChanged {
                    if let imageData = selectedImageData {
                        updatedUser = try await APIClient.shared.uploadProfilePhoto(imageData: imageData)
                    } else {
                        updatedUser = try await APIClient.shared.deleteProfilePhoto()
                    }
                }

                // 2. Update profile fields on remote server
                updatedUser = try await APIClient.shared.updateUserProfile(
                    customName: cleanName.isEmpty ? nil : cleanName,
                    bio: cleanBio.isEmpty ? nil : cleanBio,
                    avatarEmoji: selectedEmoji,
                    avatarColorHex: selectedColorHex
                )

                await MainActor.run {
                    userPreferences.customDisplayName = cleanName.isEmpty ? nil : cleanName
                    userPreferences.customBio = cleanBio.isEmpty ? nil : cleanBio
                    userPreferences.customProfileImageData = selectedImageData
                    userPreferences.customAvatarEmoji = selectedEmoji
                    userPreferences.customAvatarColorHex = selectedColorHex
                    if let user = updatedUser {
                        userPreferences.syncWithServerUser(user)
                    }
                    isSaving = false
                    HapticFeedback.light()
                    onSave()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    // Revert to previous profile image if upload failed
                    self.selectedImageData = previousImageData
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                    self.isSaving = false
                }
            }
        }
    }
}
