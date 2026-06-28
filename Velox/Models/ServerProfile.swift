import Foundation

enum ServerAuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case rsaPrivateKey
    case ed25519PrivateKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: return "Password"
        case .rsaPrivateKey: return "RSA Key"
        case .ed25519PrivateKey: return "Ed25519 Key"
        }
    }
}

struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var group: String
    var authenticationMethod: ServerAuthenticationMethod
    var privateKeyPath: String
    var lastConnectedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case username
        case group
        case authenticationMethod
        case privateKeyPath
        case lastConnectedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        group: String = "Default",
        authenticationMethod: ServerAuthenticationMethod = .password,
        privateKeyPath: String = "",
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.group = group
        self.authenticationMethod = authenticationMethod
        self.privateKeyPath = privateKeyPath
        self.lastConnectedAt = lastConnectedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        group = try container.decode(String.self, forKey: .group)
        authenticationMethod = try container.decodeIfPresent(ServerAuthenticationMethod.self, forKey: .authenticationMethod) ?? .password
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
    }
}
