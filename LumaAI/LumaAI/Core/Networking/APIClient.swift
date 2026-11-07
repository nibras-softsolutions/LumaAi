import Foundation
import Security
import CryptoKit

public struct SyncConversationsRequest: Codable {
    public let conversations: [Conversation]
    public init(conversations: [Conversation]) {
        self.conversations = conversations
    }
}

public struct EmptyResponse: Codable {
    public init() {}
}

public struct SigningCredentials {
    public let keyId: String
    public let secret: String
    public let expiresAt: Date
}

public final class SSLPinningDelegate: NSObject, URLSessionDelegate {
    public static let shared = SSLPinningDelegate()

    // Production pinned Subject Public Key Info (SPKI) SHA-256 hashes
    public static let pinnedSPKIHashes: Set<String> = [
        // Primary Leaf (*.onrender.com)
        "8emdl/UmneUm0I4Y/vHzOTQzb9eJwG4voRHtMdNmBPk=",
        // Primary Leaf raw SecKey SHA-256
        "ijMkQSEhL0wPUZ3LK8PXw3fp5E6Y3eED6o4iGJ+nhMI=",
        // Backup 1: Intermediate CA (WE1 Google Trust Services)
        "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",
        // Backup 2: Root CA (GTS Root R4 Google Trust Services)
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=",
        // Backup 3: ISRG Root X1 (Let's Encrypt Root)
        "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M="
    ]

    // ASN.1 SubjectPublicKeyInfo header for ECDSA P-256 keys (secp256r1)
    private static let p256SPKIHeader: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ]

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host.lowercased()

        #if DEBUG
        if host == "localhost" || host == "127.0.0.1" {
            var error: CFError?
            if SecTrustEvaluateWithError(serverTrust, &error) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }
        #endif

        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var evalError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &evalError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certCount = SecTrustGetCertificateCount(serverTrust)
        var hasMatchingPin = false

        for i in 0..<certCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i),
                  let publicKey = SecCertificateCopyKey(cert),
                  let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                continue
            }

            let rawKeyHash = Data(SHA256.hash(data: keyData)).base64EncodedString()
            if Self.pinnedSPKIHashes.contains(rawKeyHash) {
                hasMatchingPin = true
                break
            }

            if keyData.count == 65 && keyData.first == 0x04 {
                var spkiData = Data(Self.p256SPKIHeader)
                spkiData.append(keyData)
                let spkiHash = Data(SHA256.hash(data: spkiData)).base64EncodedString()
                if Self.pinnedSPKIHashes.contains(spkiHash) {
                    hasMatchingPin = true
                    break
                }
            }
        }

        if hasMatchingPin {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

public protocol APIClientProtocol: AnyObject {
    var configuration: APIConfiguration { get set }
    func request<T: Decodable>(_ endpoint: APIEndpoint, body: (any Encodable)?) async throws -> T
    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<ServerSentEvent, Error>
    func generateImage(prompt: String, aspectRatio: String) async throws -> ImageGenerateResponse
    func downloadImageData(from urlString: String) async throws -> Data
    func transcribeAudio(data: Data, mimeType: String) async throws -> String
    func ensureSession() async throws
    func fetchUserProfile() async throws -> User
    func updateUserProfile(customName: String?, bio: String?, avatarEmoji: String?, avatarColorHex: String?) async throws -> User
    func uploadProfilePhoto(imageData: Data) async throws -> User
    func deleteProfilePhoto() async throws -> User
    func resetUserProfile() async throws -> User
    func fetchCustomCharacters() async throws -> [CustomCharacterRemote]
    func createRemoteCustomCharacter(_ payload: CustomCharacterPayload) async throws -> CustomCharacterRemote
    func deleteRemoteCustomCharacter(id: String) async throws
    func fetchConversations() async throws -> [Conversation]
    func saveConversation(_ conversation: Conversation) async throws
    func syncConversations(_ conversations: [Conversation]) async throws -> [Conversation]
    func deleteConversation(id: UUID) async throws
    func clearAllConversations() async throws
}

public extension APIClientProtocol {
    func checkHealth() async throws -> ServerHealth {
        try await request(.health, body: nil)
    }

    func checkAIHealth() async throws -> AIHealthStatus {
        try await request(.aiHealth, body: nil)
    }

    func ensureSession() async throws {}

    func fetchUserProfile() async throws -> User {
        try await ensureSession()
        return try await request(.userProfile, body: nil)
    }

    func updateUserProfile(customName: String?, bio: String?, avatarEmoji: String?, avatarColorHex: String?) async throws -> User {
        try await ensureSession()
        let req = UpdateProfileRequest(
            customName: customName,
            bio: bio,
            avatarEmoji: avatarEmoji,
            avatarColorHex: avatarColorHex
        )
        return try await request(.updateUserProfile, body: req)
    }

    func uploadProfilePhoto(imageData: Data) async throws -> User {
        try await ensureSession()
        let base64String = "data:image/jpeg;base64," + imageData.base64EncodedString()
        let payload = UploadPhotoPayload(image: base64String)
        return try await request(.uploadProfilePhoto, body: payload)
    }

    func deleteProfilePhoto() async throws -> User {
        try await ensureSession()
        return try await request(.deleteProfilePhoto, body: nil)
    }

    func resetUserProfile() async throws -> User {
        try await ensureSession()
        return try await request(.resetUserProfile, body: nil)
    }

    func fetchCustomCharacters() async throws -> [CustomCharacterRemote] {
        try await request(.userCharacters, body: nil)
    }

    func createRemoteCustomCharacter(_ payload: CustomCharacterPayload) async throws -> CustomCharacterRemote {
        try await request(.userCharacters, body: payload)
    }

    func deleteRemoteCustomCharacter(id: String) async throws {
        let _: ServerHealth = try await request(.userCharacter(id: id), body: nil)
    }

    func fetchConversations() async throws -> [Conversation] {
        try await ensureSession()
        return try await request(.getConversations, body: nil)
    }

    func saveConversation(_ conversation: Conversation) async throws {
        try await ensureSession()
        let _: EmptyResponse = try await request(.saveConversation, body: conversation)
    }

    func syncConversations(_ conversations: [Conversation]) async throws -> [Conversation] {
        try await ensureSession()
        let req = SyncConversationsRequest(conversations: conversations)
        return try await request(.syncConversations, body: req)
    }

    func deleteConversation(id: UUID) async throws {
        try await ensureSession()
        let _: EmptyResponse = try await request(.deleteConversation(id: id.uuidString), body: nil)
    }

    func clearAllConversations() async throws {
        try await ensureSession()
        let _: EmptyResponse = try await request(.clearAllConversations, body: nil)
    }
}

public final class APIClient: APIClientProtocol {
    public static let shared = APIClient()

    public var configuration: APIConfiguration
    private let session: URLSession
    private let sseParser: SSEParser

    public init(
        configuration: APIConfiguration = APIConfiguration(),
        session: URLSession? = nil,
        sseParser: SSEParser = SSEParser()
    ) {
        self.configuration = configuration
        self.sseParser = sseParser

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpShouldSetCookies = true
            config.httpCookieAcceptPolicy = .always
            config.timeoutIntervalForRequest = 60.0
            config.timeoutIntervalForResource = 180.0
            self.session = URLSession(configuration: config, delegate: SSLPinningDelegate.shared, delegateQueue: nil)
        }
    }

    public func getStoredToken() -> String? {
        if let token = KeychainHelper.shared.readString(for: "luma_session_token"), !token.isEmpty {
            return token
        }
        if let legacy = UserDefaults.standard.string(forKey: "luma_session_token"), !legacy.isEmpty {
            KeychainHelper.shared.saveString(legacy, for: "luma_session_token")
            UserDefaults.standard.removeObject(forKey: "luma_session_token")
            return legacy
        }
        return nil
    }

    public func saveSessionToken(_ token: String) {
        KeychainHelper.shared.saveString(token, for: "luma_session_token")
        UserDefaults.standard.removeObject(forKey: "luma_session_token")
    }

    public func clearSessionToken() {
        KeychainHelper.shared.delete(for: "luma_session_token")
        KeychainHelper.shared.delete(for: "luma_signing_key_id")
        KeychainHelper.shared.delete(for: "luma_signing_secret")
        KeychainHelper.shared.delete(for: "luma_signing_expires_at")
        UserDefaults.standard.removeObject(forKey: "luma_session_token")
        cachedSigningKey = nil
    }

    private var cachedSigningKey: SigningCredentials? = nil

    public func obtainSigningKey() async throws -> SigningCredentials {
        if let cached = cachedSigningKey, cached.expiresAt > Date().addingTimeInterval(60) {
            return cached
        }
        if let keyId = KeychainHelper.shared.readString(for: "luma_signing_key_id"),
           let secret = KeychainHelper.shared.readString(for: "luma_signing_secret"),
           let expStr = KeychainHelper.shared.readString(for: "luma_signing_expires_at"),
           let exp = ISO8601DateFormatter().date(from: expStr),
           exp > Date().addingTimeInterval(60) {
            let creds = SigningCredentials(keyId: keyId, secret: secret, expiresAt: exp)
            self.cachedSigningKey = creds
            return creds
        }

        struct KeyResponse: Decodable {
            let key_id: String
            let signing_secret: String
            let expires_at: String
            let algorithm: String
        }

        let res: KeyResponse = try await request(.signingKey, body: nil)
        let expDate = ISO8601DateFormatter().date(from: res.expires_at) ?? Date().addingTimeInterval(86400)
        let creds = SigningCredentials(keyId: res.key_id, secret: res.signing_secret, expiresAt: expDate)
        self.cachedSigningKey = creds
        KeychainHelper.shared.saveString(res.key_id, for: "luma_signing_key_id")
        KeychainHelper.shared.saveString(res.signing_secret, for: "luma_signing_secret")
        KeychainHelper.shared.saveString(res.expires_at, for: "luma_signing_expires_at")
        return creds
    }

    public func signRequestIfNeeded(_ request: inout URLRequest, endpoint: APIEndpoint, bodyData: Data?) async {
        switch endpoint {
        case .updateUserProfile, .uploadProfilePhoto, .deleteProfilePhoto, .resetUserProfile, .clearAllConversations:
            break
        default:
            return
        }

        do {
            let creds = try await obtainSigningKey()
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let nonce = UUID().uuidString
            let bodyBytes = bodyData ?? Data()
            let bodyHash = SHA256.hash(data: bodyBytes).map { String(format: "%02x", $0) }.joined()
            let path = request.url?.path ?? ""
            let canonical = "\(endpoint.httpMethod.uppercased())\n\(path)\n\(timestamp)\n\(nonce)\n\(bodyHash)"

            let symmetricKey = SymmetricKey(data: Data(creds.secret.utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: symmetricKey)
            let sigHex = signature.map { String(format: "%02x", $0) }.joined()

            request.setValue(sigHex, forHTTPHeaderField: "X-Signature")
            request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
            request.setValue(nonce, forHTTPHeaderField: "X-Nonce")
            request.setValue(creds.keyId, forHTTPHeaderField: "X-Key-Id")
        } catch {
            print("[APIClient] Signing request skipped or failed: \(error)")
        }
    }

    public func ensureSession() async throws {
        let hasStoredToken = getStoredToken() != nil
        let hasCookie = HTTPCookieStorage.shared.cookies?.contains(where: { $0.name == "luma_session" }) == true
        if !hasStoredToken && !hasCookie {
            let guestId = UUID().uuidString.prefix(8).lowercased()
            let req = RegisterRequest(
                fullName: "Luma User",
                email: "guest_\(guestId)@luma.local",
                password: "Guest_\(UUID().uuidString)!"
            )
            let _: User = try await request(.register, body: req)
        }
    }

    private func saveCookies(from response: HTTPURLResponse, for url: URL?) {
        guard let requestUrl = url ?? response.url else { return }
        if let headerFields = response.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: requestUrl)
            HTTPCookieStorage.shared.setCookies(cookies, for: requestUrl, mainDocumentURL: nil)
            for cookie in cookies {
                if cookie.name == "luma_session" {
                    saveSessionToken(cookie.value)
                }
            }
        }
    }

    private func createRequest(_ endpoint: APIEndpoint, body: (any Encodable)? = nil) throws -> URLRequest {
        let url = endpoint.url(with: configuration)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var cookieDict: [String: String] = [:]
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for c in cookies {
                cookieDict[c.name] = c.value
            }
        }
        if let allCookies = HTTPCookieStorage.shared.cookies {
            for c in allCookies {
                if c.name == "luma_session" {
                    cookieDict[c.name] = c.value
                }
            }
        }
        if cookieDict["luma_session"] == nil,
           let saved = getStoredToken(),
           !saved.isEmpty {
            cookieDict["luma_session"] = saved
            request.setValue("Bearer \(saved)", forHTTPHeaderField: "Authorization")
        }

        if !cookieDict.isEmpty {
            let cookieHeader = cookieDict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    public func request<T: Decodable>(_ endpoint: APIEndpoint, body: (any Encodable)? = nil) async throws -> T {
        var urlRequest = try createRequest(endpoint, body: body)
        await signRequestIfNeeded(&urlRequest, endpoint: endpoint, bodyData: urlRequest.httpBody)
        let (data, response) = try await perform(urlRequest)

        saveCookies(from: response, for: urlRequest.url)

        if data.isEmpty {
            if T.self == ServerHealth.self {
                return ServerHealth(status: "ok") as! T
            }
            if let empty = EmptyResponse() as? T {
                return empty
            }
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error.localizedDescription)
        }
    }

    public func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = APIEndpoint.chatStream
                    let payloads = messages
                        .filter { ($0.role == .user || $0.role == .assistant) && $0.status == .complete && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .suffix(20)
                        .map { SendMessagePayload(role: $0.role.rawValue, content: $0.content) }

                    guard !payloads.isEmpty, payloads.last?.role == "user" else {
                        continuation.finish()
                        return
                    }

                    var urlRequest = try createRequest(endpoint, body: ChatStreamRequest(messages: Array(payloads)))
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    var (bytes, response) = try await session.bytes(for: urlRequest)
                    guard var httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: NetworkError.invalidResponse)
                        return
                    }

                    saveCookies(from: httpResponse, for: urlRequest.url)

                    // Auto-refresh session on 401 Unauthorized
                    if httpResponse.statusCode == 401 {
                        let guestId = UUID().uuidString.prefix(8).lowercased()
                        let regReq = RegisterRequest(
                            fullName: "Luma User",
                            email: "guest_\(guestId)@luma.local",
                            password: "Guest_\(UUID().uuidString)!"
                        )
                        let _: User = try await request(.register, body: regReq)

                        // Recreate request with new session cookie
                        urlRequest = try createRequest(endpoint, body: ChatStreamRequest(messages: payloads))
                        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let retryRes = try await session.bytes(for: urlRequest)
                        bytes = retryRes.0
                        if let retryHttp = retryRes.1 as? HTTPURLResponse {
                            httpResponse = retryHttp
                            saveCookies(from: retryHttp, for: urlRequest.url)
                        }
                    }

                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: NetworkError.unauthorized)
                        return
                    }
                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: NetworkError.rateLimited("Rate limit reached. Please wait."))
                        return
                    }
                    if !(200...299).contains(httpResponse.statusCode) {
                        continuation.finish(throwing: NetworkError.serverError(statusCode: httpResponse.statusCode, message: "Chat streaming failed (\(httpResponse.statusCode))."))
                        return
                    }

                    var currentEventName = "token"
                    var currentDataBuffer = ""

                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

                        if line.hasPrefix("event:") {
                            if !currentDataBuffer.isEmpty {
                                let parsed = sseParser.parse(event: currentEventName, dataString: currentDataBuffer)
                                continuation.yield(parsed)
                                currentDataBuffer = ""
                            }
                            currentEventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if line.hasPrefix("data:") {
                            let dataContent = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                            let parsed = sseParser.parse(event: currentEventName, dataString: dataContent)
                            continuation.yield(parsed)
                            if parsed == .done {
                                break
                            }
                            currentEventName = "token"
                            currentDataBuffer = ""
                        } else if line.isEmpty {
                            if !currentDataBuffer.isEmpty || currentEventName == "done" {
                                let parsed = sseParser.parse(event: currentEventName, dataString: currentDataBuffer)
                                continuation.yield(parsed)
                                if parsed == .done {
                                    break
                                }
                                currentEventName = "token"
                                currentDataBuffer = ""
                            }
                        }
                    }

                    if !currentDataBuffer.isEmpty || currentEventName == "done" {
                        let parsed = sseParser.parse(event: currentEventName, dataString: currentDataBuffer)
                        continuation.yield(parsed)
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: NetworkError.cancelled)
                    } else if let urlError = error as? URLError {
                        continuation.finish(throwing: mapURLError(urlError))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func generateImage(prompt: String, aspectRatio: String = "1:1") async throws -> ImageGenerateResponse {
        let endpoint = APIEndpoint.generateImage
        let req = ImageGenerateRequest(prompt: prompt, aspectRatio: aspectRatio)
        return try await request(endpoint, body: req)
    }

    public func downloadImageData(from urlString: String) async throws -> Data {
        let fullURL: URL
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            guard let parsed = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }
            fullURL = parsed
        } else {
            let path = urlString.hasPrefix("/") ? String(urlString.dropFirst()) : urlString
            if #available(iOS 16.0, macOS 13.0, *) {
                fullURL = configuration.baseURL.appending(path: path)
            } else {
                var url = configuration.baseURL
                for comp in path.split(separator: "/") {
                    url = url.appendingPathComponent(String(comp))
                }
                fullURL = url
            }
        }

        var req = URLRequest(url: fullURL)
        req.httpMethod = "GET"
        let (data, _) = try await perform(req)
        return data
    }

    public func transcribeAudio(data: Data, mimeType: String = "audio/webm") async throws -> String {
        let url = APIEndpoint.transcribeVoice.url(with: configuration)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (responseData, _) = try await perform(req)
        do {
            let res = try JSONDecoder().decode(VoiceTranscriptionResponse.self, from: responseData)
            return res.text
        } catch {
            throw NetworkError.decodingError("Could not decode transcription response.")
        }
    }

    @discardableResult
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            saveCookies(from: http, for: request.url)

            if http.statusCode == 401 {
                throw NetworkError.unauthorized
            }
            if http.statusCode == 403 {
                let msg = parseErrorMessage(from: data) ?? "Access forbidden."
                throw NetworkError.forbidden(msg)
            }
            if http.statusCode == 404 {
                if let msg = parseErrorMessage(from: data), !msg.isEmpty {
                    throw NetworkError.serverError(statusCode: 404, message: msg)
                }
                throw NetworkError.notFound
            }
            if http.statusCode == 429 {
                let msg = parseErrorMessage(from: data) ?? "Too many requests. Please wait."
                throw NetworkError.rateLimited(msg)
            }
            if !(200...299).contains(http.statusCode) {
                let msg = parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                throw NetworkError.serverError(statusCode: http.statusCode, message: msg)
            }

            return (data, http)
        } catch let err as NetworkError {
            throw err
        } catch let urlErr as URLError {
            throw mapURLError(urlErr)
        } catch {
            throw NetworkError.unknown(error.localizedDescription)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let detail = json["detail"] as? String {
            return detail
        }
        if let message = json["message"] as? String {
            return message
        }
        return nil
    }

    private func mapURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
