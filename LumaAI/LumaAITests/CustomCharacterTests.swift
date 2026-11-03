import XCTest
@testable import LumaAI

final class CustomCharacterTests: XCTestCase {

    var userPrefs: UserPreferences!

    override func setUp() {
        super.setUp()
        userPrefs = UserPreferences(defaults: UserDefaults(suiteName: "test_characters_suite") ?? .standard)
        userPrefs.resetProfileCustomization()
        userPrefs.userCharacters = []
        userPrefs.activeCharacterId = "char_luma_default"
    }

    override func tearDown() {
        userPrefs.resetProfileCustomization()
        userPrefs.userCharacters = []
        userPrefs = nil
        super.tearDown()
    }

    func testBuiltInCharacters() {
        let builtIns = CustomCharacter.builtInCharacters
        XCTAssertEqual(builtIns.count, 5)
        XCTAssertEqual(builtIns[0].id, "char_luma_default")
        XCTAssertEqual(builtIns[0].name, "Luma AI")
        XCTAssertTrue(builtIns[0].isBuiltIn)

        XCTAssertEqual(builtIns[1].name, "Code Architect")
        XCTAssertEqual(builtIns[2].name, "Creative Writer")
        XCTAssertEqual(builtIns[3].name, "Philosopher")
        XCTAssertEqual(builtIns[4].name, "Executive")
    }

    func testProfileCustomizationAndReset() {
        XCTAssertNil(userPrefs.customDisplayName)
        XCTAssertNil(userPrefs.customBio)

        userPrefs.customDisplayName = "Alex Developer"
        userPrefs.customBio = "Building agentic AI tools"
        userPrefs.customAvatarEmoji = "🧑‍💻"
        userPrefs.customAvatarColorHex = "#2563EB"

        XCTAssertEqual(userPrefs.customDisplayName, "Alex Developer")
        XCTAssertEqual(userPrefs.customBio, "Building agentic AI tools")
        XCTAssertEqual(userPrefs.customAvatarEmoji, "🧑‍💻")
        XCTAssertEqual(userPrefs.customAvatarColorHex, "#2563EB")

        userPrefs.resetProfileCustomization()

        XCTAssertNil(userPrefs.customDisplayName)
        XCTAssertNil(userPrefs.customBio)
        XCTAssertNil(userPrefs.customAvatarEmoji)
        XCTAssertNil(userPrefs.customAvatarColorHex)
    }

    func testAddEditDeleteCustomCharacter() {
        let initialCount = userPrefs.allCharacters.count

        let newChar = CustomCharacter(
            name: "Physics Tutor",
            tagline: "Quantum & classical mechanics",
            avatarEmoji: "⚛️",
            accentColorHex: "#8B5CF6",
            systemPrompt: "You are an expert physics tutor."
        )

        userPrefs.addCustomCharacter(newChar)
        XCTAssertEqual(userPrefs.allCharacters.count, initialCount + 1)
        XCTAssertEqual(userPrefs.userCharacters.count, 1)

        userPrefs.activeCharacterId = newChar.id
        XCTAssertEqual(userPrefs.activeCharacter.name, "Physics Tutor")

        // Edit
        var edited = newChar
        edited.name = "Advanced Physics Professor"
        userPrefs.updateCustomCharacter(edited)
        XCTAssertEqual(userPrefs.activeCharacter.name, "Advanced Physics Professor")

        // Delete
        userPrefs.deleteCustomCharacter(id: newChar.id)
        XCTAssertEqual(userPrefs.userCharacters.count, 0)
        XCTAssertEqual(userPrefs.allCharacters.count, initialCount)
        XCTAssertEqual(userPrefs.activeCharacterId, "char_luma_default")
    }
}
