import SwiftUI

public struct EditCharacterView: View {
    @ObservedObject var userPreferences: UserPreferences
    let characterToEdit: CustomCharacter?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var tagline: String = ""
    @State private var avatarEmoji: String = "✨"
    @State private var accentColorHex: String = "#FFC43D"
    @State private var systemPrompt: String = ""
    @State private var showingDeleteAlert: Bool = false

    private let characterEmojis: [String] = ["✨", "👨‍💻", "🎨", "🦉", "⚡️", "🤖", "🚀", "🔬", "📚", "🎭", "🧘", "💼"]
    private let colorOptions: [(name: String, hex: String)] = [
        ("Gold", "#FFC43D"),
        ("Blue", "#2563EB"),
        ("Purple", "#8B5CF6"),
        ("Emerald", "#10B981"),
        ("Rose", "#EC4899"),
        ("Cyan", "#06B6D4")
    ]

    public init(
        userPreferences: UserPreferences = .shared,
        characterToEdit: CustomCharacter? = nil,
        onSave: @escaping () -> Void = {}
    ) {
        self.userPreferences = userPreferences
        self.characterToEdit = characterToEdit
        self.onSave = onSave

        if let char = characterToEdit {
            _name = State(initialValue: char.name)
            _tagline = State(initialValue: char.tagline)
            _avatarEmoji = State(initialValue: char.avatarEmoji)
            _accentColorHex = State(initialValue: char.accentColorHex)
            _systemPrompt = State(initialValue: char.systemPrompt)
        } else {
            _name = State(initialValue: "")
            _tagline = State(initialValue: "")
            _avatarEmoji = State(initialValue: "✨")
            _accentColorHex = State(initialValue: "#2563EB")
            _systemPrompt = State(initialValue: "You are a specialized AI assistant. Adopt this persona in all responses.")
        }
    }

    private var isEditingExisting: Bool {
        characterToEdit != nil
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Avatar & Name Preview
                    characterPreview

                    // Avatar Emoji Picker
                    emojiPickerSection

                    // Color Picker
                    colorPickerSection

                    // Fields
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHARACTER NAME")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.settingsSectionLabel)

                            TextField("e.g. Socratic Tutor", text: $name)
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
                            Text("TAGLINE / ROLE")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.settingsSectionLabel)

                            TextField("e.g. Critical thinking and dialogue", text: $tagline)
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
                            Text("SYSTEM INSTRUCTIONS / PERSONALITY")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.settingsSectionLabel)

                            TextEditor(text: $systemPrompt)
                                .font(.system(size: 14))
                                .foregroundColor(.settingsPrimaryText)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(10)
                                .background(Color.settingsCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.settingsDivider, lineWidth: 1)
                                )

                            Text("Instruct the AI on its personality, tone, vocabulary, and expertise domain.")
                                .font(.system(size: 12))
                                .foregroundColor(.settingsSecondaryText)
                                .padding(.horizontal, 4)
                        }
                    }

                    // Delete Action (if editing user-created character)
                    if let char = characterToEdit, !char.isBuiltIn {
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Character")
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
            .navigationTitle(isEditingExisting ? "Edit Character" : "New Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.settingsSecondaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCharacter()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isValid ? Color.lumaInversePrimaryText : Color.lumaInversePrimaryText.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(isValid ? Color.settingsPrimaryText : Color.gray.opacity(0.4))
                    .clipShape(Capsule())
                    .disabled(!isValid)
                }
            }
            .confirmationDialog("Delete Custom Character?", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
                Button("Delete Character", role: .destructive) {
                    if let char = characterToEdit {
                        userPreferences.deleteCustomCharacter(id: char.id)
                        HapticFeedback.warning()
                        onSave()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this character? This cannot be undone.")
            }
        }
    }

    private var characterPreview: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color(hex: accentColorHex).opacity(0.18))
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(Color(hex: accentColorHex), lineWidth: 2)
                )
                .overlay(
                    Text(avatarEmoji)
                        .font(.system(size: 38))
                )

            Text(name.isEmpty ? "Character Name" : name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.settingsPrimaryText)

            if !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 13))
                    .foregroundColor(.settingsSecondaryText)
            }
        }
        .padding(.top, 8)
    }

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHARACTER ICON")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.settingsSectionLabel)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(characterEmojis, id: \.self) { emoji in
                    Button(action: {
                        HapticFeedback.selection()
                        avatarEmoji = emoji
                    }) {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .background(avatarEmoji == emoji ? Color.settingsCard : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(avatarEmoji == emoji ? Color.settingsPrimaryText : Color.clear, lineWidth: 1.5)
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
                    Button(action: {
                        HapticFeedback.selection()
                        accentColorHex = item.hex
                    }) {
                        Circle()
                            .fill(Color(hex: item.hex))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle()
                                    .stroke(Color.settingsCard, lineWidth: accentColorHex == item.hex ? 2.5 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.settingsPrimaryText, lineWidth: accentColorHex == item.hex ? 1.5 : 0)
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

    private func saveCharacter() {
        guard isValid else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTagline = tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if var existing = characterToEdit {
            existing.name = cleanName
            existing.tagline = cleanTagline
            existing.avatarEmoji = avatarEmoji
            existing.accentColorHex = accentColorHex
            existing.systemPrompt = cleanPrompt
            userPreferences.updateCustomCharacter(existing)
        } else {
            let newChar = CustomCharacter(
                name: cleanName,
                tagline: cleanTagline,
                avatarEmoji: avatarEmoji,
                accentColorHex: accentColorHex,
                systemPrompt: cleanPrompt,
                isBuiltIn: false
            )
            userPreferences.addCustomCharacter(newChar)
            userPreferences.activeCharacterId = newChar.id
        }

        HapticFeedback.light()
        onSave()
        dismiss()
    }
}
