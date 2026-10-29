import XCTest
@testable import LumaAI
import UIKit

final class MockAPIClient: APIClientProtocol {
    var configuration: APIConfiguration = APIConfiguration()
    var streamEventsToYield: [ServerSentEvent] = [.token("Hello from Luma AI!"), .done]
    var shouldFailStream: Bool = false

    func request<T: Decodable>(_ endpoint: APIEndpoint, body: (any Encodable)?) async throws -> T {
        throw NetworkError.serverError(statusCode: 404, message: "Not implemented in mock")
    }

    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            if shouldFailStream {
                continuation.finish(throwing: NetworkError.serverError(statusCode: 500, message: "Stream failed"))
                return
            }
            for event in streamEventsToYield {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func generateImage(prompt: String, aspectRatio: String) async throws -> ImageGenerateResponse {
        return ImageGenerateResponse(
            id: "img_mock_123",
            prompt: prompt,
            aspectRatio: aspectRatio,
            imageUrl: "/api/image/view/img_mock_123",
            width: 1024,
            height: 1024,
            provider: "mock",
            model: "mock-model",
            createdAt: 1700000000
        )
    }

    func downloadImageData(from urlString: String) async throws -> Data {
        return Data()
    }

    func transcribeAudio(data: Data, mimeType: String) async throws -> String {
        return "Transcribed voice text"
    }

    func ensureSession() async throws {}
}

final class MockConversationStore: ConversationStoreProtocol {
    var savedConversations: [Conversation] = []

    func loadConversations(for userId: String) -> [Conversation] {
        return savedConversations
    }

    func saveConversations(_ conversations: [Conversation], for userId: String) {
        self.savedConversations = conversations
    }

    func deleteConversations(for userId: String) {
        self.savedConversations.removeAll()
    }
}

@MainActor
final class ChatViewModelTests: XCTestCase {

    var mockAPI: MockAPIClient!
    var mockStore: MockConversationStore!
    var viewModel: ChatViewModel!
    let testUserId = "user_test_99"

    override func setUp() {
        super.setUp()
        mockAPI = MockAPIClient()
        mockStore = MockConversationStore()
        viewModel = ChatViewModel(
            apiClient: mockAPI,
            conversationStore: mockStore,
            userId: testUserId
        )
    }

    override func tearDown() {
        viewModel = nil
        mockStore = nil
        mockAPI = nil
        super.tearDown()
    }

    func testSendMessageAppendsUserMessageAndStreamsReply() async {
        viewModel.inputText = "What is quantum computing?"
        viewModel.sendMessage()

        XCTAssertEqual(viewModel.inputText, "")
        XCTAssertEqual(viewModel.conversation.messages.count, 2)
        XCTAssertEqual(viewModel.conversation.messages[0].role, .user)
        XCTAssertEqual(viewModel.conversation.messages[0].content, "What is quantum computing?")
        XCTAssertEqual(viewModel.conversation.title, "What is quantum computing?")

        // Allow async streaming task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.conversation.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.conversation.messages[1].content, "Hello from Luma AI!")
        XCTAssertEqual(viewModel.conversation.messages[1].status, .complete)
        XCTAssertEqual(mockStore.savedConversations.count, 1)
    }

    func testSendMessageWithAttachedImage() async {
        // Create a small 1x1 test image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let testImage = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        viewModel.inputText = "Analyze this diagram"
        viewModel.attachedImage = testImage
        viewModel.sendMessage()

        XCTAssertNil(viewModel.attachedImage)
        XCTAssertEqual(viewModel.conversation.messages.first?.role, .user)
        XCTAssertNotNil(viewModel.conversation.messages.first?.imageAttachment)
        XCTAssertTrue(viewModel.conversation.messages.first?.imageAttachment?.imageUrl.hasPrefix("data:image/jpeg;base64,") == true)
    }

    func testStartNewConversationResetsState() {
        viewModel.inputText = "Temp query"
        viewModel.sendMessage()

        viewModel.startNewConversation()

        XCTAssertEqual(viewModel.conversation.messages.count, 0)
        XCTAssertEqual(viewModel.conversation.title, "New Conversation")
        XCTAssertEqual(viewModel.inputText, "")
        XCTAssertNil(viewModel.attachedImage)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDictationStateControl() {
        XCTAssertFalse(viewModel.isDictating)
        viewModel.stopDictation()
        XCTAssertFalse(viewModel.isDictating)
    }
}
