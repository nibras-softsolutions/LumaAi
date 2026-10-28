import Foundation

public struct User: Codable, Identifiable, Equatable {
    public let id: String
    public var fullName: String
    public var email: String

    public init(id: String, fullName: String, email: String) {
        self.id = id
        self.fullName = fullName
        self.email = email
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
    }
}

public struct LoginRequest: Codable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct RegisterRequest: Codable {
    public let fullName: String
    public let email: String
    public let password: String

    public init(fullName: String, email: String, password: String) {
        self.fullName = fullName
        self.email = email
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case password
    }
}
