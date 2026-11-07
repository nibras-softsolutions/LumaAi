import XCTest
@testable import LumaAI

final class APIEndpointTests: XCTestCase {

    var config: APIConfiguration!

    override func setUp() {
        super.setUp()
        config = APIConfiguration(baseURL: URL(string: "https://lumaai-j0u3.onrender.com")!)
    }

    func testEndpointURLs() {
        XCTAssertEqual(APIEndpoint.health.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/health")
        XCTAssertEqual(APIEndpoint.aiHealth.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/health/ai")
        XCTAssertEqual(APIEndpoint.chatStream.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/chat/stream")
        XCTAssertEqual(APIEndpoint.imageGenerate.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/image/generate")
        XCTAssertEqual(APIEndpoint.imageView(id: "img_42").url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/image/view/img_42")
        XCTAssertEqual(APIEndpoint.login.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/auth/login")
        XCTAssertEqual(APIEndpoint.googleAuth.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/auth/google")
        XCTAssertEqual(APIEndpoint.register.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/auth/register")
        XCTAssertEqual(APIEndpoint.me.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/auth/me")
        XCTAssertEqual(APIEndpoint.logout.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/auth/logout")
        XCTAssertEqual(APIEndpoint.userProfile.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/user/profile")
        XCTAssertEqual(APIEndpoint.updateUserProfile.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/user/profile")
        XCTAssertEqual(APIEndpoint.uploadProfilePhoto.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/user/profile/photo")
        XCTAssertEqual(APIEndpoint.deleteProfilePhoto.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/user/profile/photo")
        XCTAssertEqual(APIEndpoint.resetUserProfile.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/user/profile")
        XCTAssertEqual(APIEndpoint.userCharacters.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/user/characters")
        XCTAssertEqual(APIEndpoint.getConversations.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/chat/conversations")
        XCTAssertEqual(APIEndpoint.saveConversation.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/chat/conversations")
        XCTAssertEqual(APIEndpoint.deleteConversation(id: "123").url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/chat/conversations/123")
        XCTAssertEqual(APIEndpoint.clearAllConversations.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/chat/conversations")
        XCTAssertEqual(APIEndpoint.syncConversations.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/chat/sync")
        XCTAssertEqual(APIEndpoint.signingKey.url(with: config).absoluteString, "https://lumaai-j0u3.onrender.com/api/auth/signing-key")
    }

    func testEndpointHTTPMethods() {
        XCTAssertEqual(APIEndpoint.health.httpMethod, "GET")
        XCTAssertEqual(APIEndpoint.aiHealth.httpMethod, "GET")
        XCTAssertEqual(APIEndpoint.chatStream.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.imageGenerate.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.login.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.googleAuth.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.register.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.logout.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.me.httpMethod, "GET")
        XCTAssertEqual(APIEndpoint.userProfile.httpMethod, "GET")
        XCTAssertEqual(APIEndpoint.updateUserProfile.httpMethod, "PUT")
        XCTAssertEqual(APIEndpoint.uploadProfilePhoto.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.deleteProfilePhoto.httpMethod, "DELETE")
        XCTAssertEqual(APIEndpoint.resetUserProfile.httpMethod, "DELETE")
        XCTAssertEqual(APIEndpoint.userCharacters.httpMethod, "GET")
        XCTAssertEqual(APIEndpoint.getConversations.httpMethod, "GET")
        XCTAssertEqual(APIEndpoint.saveConversation.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.deleteConversation(id: "123").httpMethod, "DELETE")
        XCTAssertEqual(APIEndpoint.clearAllConversations.httpMethod, "DELETE")
        XCTAssertEqual(APIEndpoint.syncConversations.httpMethod, "POST")
        XCTAssertEqual(APIEndpoint.signingKey.httpMethod, "POST")
    }
}
