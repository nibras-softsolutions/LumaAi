import XCTest
@testable import LumaAI

final class ConversationStoreTests: XCTestCase {

    var store: ConversationStore!
    let testUserA = "test_user_a_\(UUID().uuidString)"
    let testUserB = "test_user_b_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        store = ConversationStore()
    }

    override func tearDown() {
        store.deleteConversations(for: testUserA)
        store.deleteConversations(for: testUserB)
        super.tearDown()
    }

    func testSaveAndLoadConversations() {
        var conv = Conversation(title: "Architecture Discussion")
        let msg1 = ChatMessage(role: .user, content: "Explain clean architecture in iOS")
        let msg2 = ChatMessage(role: .assistant, content: "Clean architecture separates concern...")
        conv.messages = [msg1, msg2]

        store.saveConversations([conv], for: testUserA)

        let loaded = store.loadConversations(for: testUserA)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conv.id)
        XCTAssertEqual(loaded.first?.title, "Architecture Discussion")
        XCTAssertEqual(loaded.first?.messages.count, 2)
        XCTAssertEqual(loaded.first?.messages.first?.content, "Explain clean architecture in iOS")
    }

    func testUserIsolation() {
        let convA = Conversation(title: "User A Conversation")
        let convB = Conversation(title: "User B Conversation")

        store.saveConversations([convA], for: testUserA)
        store.saveConversations([convB], for: testUserB)

        let loadedA = store.loadConversations(for: testUserA)
        let loadedB = store.loadConversations(for: testUserB)

        XCTAssertEqual(loadedA.count, 1)
        XCTAssertEqual(loadedA.first?.title, "User A Conversation")

        XCTAssertEqual(loadedB.count, 1)
        XCTAssertEqual(loadedB.first?.title, "User B Conversation")
    }

    func testDeleteConversations() {
        let conv = Conversation(title: "Temporary conversation")
        store.saveConversations([conv], for: testUserA)
        XCTAssertEqual(store.loadConversations(for: testUserA).count, 1)

        store.deleteConversations(for: testUserA)
        XCTAssertTrue(store.loadConversations(for: testUserA).isEmpty)
    }
}
