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
    }
}
