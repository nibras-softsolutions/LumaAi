import XCTest
@testable import LumaAI

@MainActor
final class SettingsViewModelTests: XCTestCase {

    var mockAPI: MockAPIClient!
    var authManager: AuthenticationManager!
    var userPrefs: UserPreferences!
    var viewModel: SettingsViewModel!

    override func setUp() {
        super.setUp()
        mockAPI = MockAPIClient()
        authManager = AuthenticationManager(apiClient: mockAPI)
        authManager.setMockAuthenticatedUser()
        userPrefs = UserPreferences(defaults: UserDefaults(suiteName: "test_settings_suite") ?? .standard)
        viewModel = SettingsViewModel(
            authManager: authManager,
            userPreferences: userPrefs,
            apiClient: mockAPI
        )
    }

    override func tearDown() {
        viewModel = nil
        userPrefs = nil
        authManager = nil
        mockAPI = nil
        super.tearDown()
    }

    func testInitialStatusState() {
        XCTAssertEqual(viewModel.statusState, .loading)
    }

    func testResetVoiceSettings() {
        userPrefs.voiceSpeakingRate = 0.60
        userPrefs.voicePitchMultiplier = 1.25

        viewModel.resetVoiceSettings()

        XCTAssertEqual(userPrefs.voiceSpeakingRate, 0.49, accuracy: 0.001)
        XCTAssertEqual(userPrefs.voicePitchMultiplier, 1.10, accuracy: 0.001)
        XCTAssertFalse(viewModel.isPlayingSample)
    }

    func testFormattedLastChecked() {
        XCTAssertEqual(viewModel.formattedLastChecked, "Not checked yet")

        viewModel.lastCheckedTime = Date()
        XCTAssertTrue(viewModel.formattedLastChecked.hasPrefix("Checked at"))
    }

    func testStatusStateWhenServerHealthy() {
        viewModel.serverHealth = ServerHealth(status: "ok")
        viewModel.aiHealth = AIHealthStatus(status: "ok", model: "openai/gpt-oss-120b", ollamaConnected: true, modelAvailable: true)

        XCTAssertEqual(viewModel.statusState, .operational)
    }

    func testStatusStateWhenDegraded() {
        viewModel.serverHealth = ServerHealth(status: "ok")
        viewModel.aiHealth = AIHealthStatus(status: "degraded", model: "openai/gpt-oss-120b", ollamaConnected: false, modelAvailable: false)

        XCTAssertEqual(viewModel.statusState, .degraded)
    }

    func testStatusStateWhenUnavailable() {
        viewModel.serverHealth = nil
        viewModel.healthError = "Network connection lost"

        XCTAssertEqual(viewModel.statusState, .unavailable)
    }

    func testLogoutClearsSession() async {
        XCTAssertTrue(authManager.isAuthenticated)

        await viewModel.logout()

        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }
}
