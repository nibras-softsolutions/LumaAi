import XCTest
@testable import LumaAI

final class ModelDecodingTests: XCTestCase {

    func testUserDecoding() throws {
        let json = """
        {
            "id": "usr_9988aabb",
            "full_name": "Ada Lovelace",
            "email": "ada@example.com"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let user = try decoder.decode(User.self, from: json)

        XCTAssertEqual(user.id, "usr_9988aabb")
        XCTAssertEqual(user.fullName, "Ada Lovelace")
        XCTAssertEqual(user.email, "ada@example.com")
    }

    func testServerHealthDecoding() throws {
        let json = """
        {
            "status": "ok"
        }
        """.data(using: .utf8)!

        let health = try JSONDecoder().decode(ServerHealth.self, from: json)
        XCTAssertEqual(health.status, "ok")
    }

    func testAIHealthStatusDecoding() throws {
        let json = """
        {
            "status": "ok",
            "model": "openai/gpt-oss-120b",
            "ollama_connected": true,
            "model_available": true
        }
        """.data(using: .utf8)!

        let aiHealth = try JSONDecoder().decode(AIHealthStatus.self, from: json)
        XCTAssertEqual(aiHealth.status, "ok")
        XCTAssertEqual(aiHealth.ollamaConnected, true)
        XCTAssertEqual(aiHealth.modelAvailable, true)
    }

    func testImageGenerateResponseDecoding() throws {
        let json = """
        {
            "id": "img_12345678",
            "prompt": "A serene neon bonsai tree",
            "aspect_ratio": "16:9",
            "image_url": "/api/image/view/img_12345678",
            "width": 1280,
            "height": 720,
            "provider": "Pollinations FLUX",
            "model": "flux",
            "created_at": 1729000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ImageGenerateResponse.self, from: json)
        XCTAssertEqual(response.id, "img_12345678")
        XCTAssertEqual(response.prompt, "A serene neon bonsai tree")
        XCTAssertEqual(response.aspectRatio, "16:9")
        XCTAssertEqual(response.imageUrl, "/api/image/view/img_12345678")
        XCTAssertEqual(response.width, 1280)
        XCTAssertEqual(response.height, 720)
        XCTAssertEqual(response.provider, "Pollinations FLUX")
        XCTAssertEqual(response.model, "flux")
    }

    func testChatMessageEncodingAndDecoding() throws {
        let original = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Hello! How can I help you?",
            status: .complete
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.status, original.status)
    }
}
