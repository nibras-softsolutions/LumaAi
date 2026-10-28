import Foundation

public enum NetworkError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden(String)
    case notFound
    case rateLimited(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case timeout
    case offline
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .unauthorized:
            return "Authentication required. Please sign in to continue."
        case .forbidden(let msg):
            return msg.isEmpty ? "Access forbidden." : msg
        case .notFound:
            return "Requested resource was not found."
        case .rateLimited(let msg):
            return msg.isEmpty ? "Rate limit reached. Please wait a moment." : msg
        case .serverError(let code, let msg):
            return msg.isEmpty ? "Server error (\(code))." : msg
        case .decodingError(let msg):
            return "Failed to parse data: \(msg)"
        case .timeout:
            return "Request timed out. The server may be waking up, please try again."
        case .offline:
            return "No internet connection detected. Please check your network."
        case .cancelled:
            return "Request was cancelled."
        case .unknown(let msg):
            return msg
        }
    }
}
