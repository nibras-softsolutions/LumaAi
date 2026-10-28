import Foundation

public protocol APIClientProtocol: AnyObject {
    var configuration: APIConfiguration { get set }
    func request<T: Decodable>(_ endpoint: APIEndpoint, body: (any Encodable)?) async throws -> T
    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<ServerSentEvent, Error>
    func generateImage(prompt: String, aspectRatio: String) async throws -> ImageGenerateResponse
    func downloadImageData(from urlString: String) async throws -> Data
    func transcribeAudio(data: Data, mimeType: String) async throws -> String
    func ensureSession() async throws
}

public extension APIClientProtocol {
    func checkHealth() async throws -> ServerHealth {
        try await request(.health, body: nil)
    }

    func checkAIHealth() async throws -> AIHealthStatus {
        try await request(.aiHealth, body: nil)
    }

    func ensureSession() async throws {}
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
            self.session = URLSession(configuration: config)
        }
    }

    public func ensureSession() async throws {
        let hasStoredToken = UserDefaults.standard.string(forKey: "luma_session_token") != nil
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
                    UserDefaults.standard.set(cookie.value, forKey: "luma_session_token")
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
           let saved = UserDefaults.standard.string(forKey: "luma_session_token"),
           !saved.isEmpty {
            cookieDict["luma_session"] = saved
        }

        if !cookieDict.isEmpty {
            let cookieHeader = cookieDict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    public func request<T: Decodable>(_ endpoint: APIEndpoint, body: (any Encodable)? = nil) async throws -> T {
        let urlRequest = try createRequest(endpoint, body: body)
        let (data, response) = try await perform(urlRequest)

        saveCookies(from: response, for: urlRequest.url)

        if T.self == ServerHealth.self && data.isEmpty {
            return ServerHealth(status: "ok") as! T
        }

        do {
            let decoder = JSONDecoder()
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
                        .filter { $0.status == .complete && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .map { SendMessagePayload(role: $0.role.rawValue, content: $0.content) }

                    guard !payloads.isEmpty else {
                        continuation.finish()
                        return
                    }

                    var urlRequest = try createRequest(endpoint, body: ChatStreamRequest(messages: payloads))
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
            fullURL = configuration.baseURL.appendingPathComponent(path)
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
