import Foundation

public struct CustomCharacter: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var tagline: String
    public var avatarEmoji: String
    public var accentColorHex: String
    public var systemPrompt: String
    public var isBuiltIn: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        tagline: String,
        avatarEmoji: String,
        accentColorHex: String = "#2563EB",
        systemPrompt: String,
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.avatarEmoji = avatarEmoji
        self.accentColorHex = accentColorHex
        self.systemPrompt = systemPrompt
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    public static let builtInCharacters: [CustomCharacter] = [
        CustomCharacter(
            id: "char_luma_default",
            name: "Luma AI",
            tagline: "Thoughtful & articulate AI companion",
            avatarEmoji: "✨",
            accentColorHex: "#FFC43D",
            systemPrompt: "You are Luma AI, a thoughtful, creative, and intellectually curious AI companion. Provide articulate, well-structured, and insightful answers.",
            isBuiltIn: true
        ),
        CustomCharacter(
            id: "char_code_architect",
            name: "Code Architect",
            tagline: "Senior engineer for clean code & systems",
            avatarEmoji: "👨‍💻",
            accentColorHex: "#2563EB",
            systemPrompt: "You are Code Architect, a senior software architect specializing in Swift, Python, clean architecture, and performance. Deliver production-grade, maintainable code with clear explanations.",
            isBuiltIn: true
        ),
        CustomCharacter(
            id: "char_creative_writer",
            name: "Creative Writer",
            tagline: "Novelist, poet, and visual storyteller",
            avatarEmoji: "🎨",
            accentColorHex: "#EC4899",
            systemPrompt: "You are Creative Writer, a gifted novelist, essayist, and poet. Craft vivid imagery, compelling narratives, resonant metaphors, and engaging storytelling.",
            isBuiltIn: true
        ),
        CustomCharacter(
            id: "char_philosophical_thinker",
            name: "Philosopher",
            tagline: "First-principles inquiry & deep contemplation",
            avatarEmoji: "🦉",
            accentColorHex: "#8B5CF6",
            systemPrompt: "You are Philosophical Thinker. You examine complex problems through first principles, Socratic dialogue, epistemology, and rigorous critical thinking.",
            isBuiltIn: true
        ),
        CustomCharacter(
            id: "char_concise_executive",
            name: "Executive",
            tagline: "Action-oriented bullet points & key takeaways",
            avatarEmoji: "⚡️",
            accentColorHex: "#10B981",
            systemPrompt: "You are Concise Executive. You deliver punchy, high-impact answers. Avoid fluff. Provide executive summaries, direct recommendations, and structured action items.",
            isBuiltIn: true
        )
    ]
}
