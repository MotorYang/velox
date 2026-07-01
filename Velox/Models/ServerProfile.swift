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
    var hasStoredSecret: Bool
    var lastConnectedAt: Date?
    var sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case username
        case group
        case authenticationMethod
        case privateKeyPath
        case hasStoredSecret
        case lastConnectedAt
        case sortOrder
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
        hasStoredSecret: Bool = false,
        lastConnectedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.group = group
        self.authenticationMethod = authenticationMethod
        self.privateKeyPath = privateKeyPath
        self.hasStoredSecret = hasStoredSecret
        self.lastConnectedAt = lastConnectedAt
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        group = try container.decode(String.self, forKey: .group)
        let decodedAuthenticationMethod = try container.decodeIfPresent(ServerAuthenticationMethod.self, forKey: .authenticationMethod) ?? .password
        authenticationMethod = decodedAuthenticationMethod
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        hasStoredSecret = try container.decodeIfPresent(Bool.self, forKey: .hasStoredSecret) ?? (decodedAuthenticationMethod == .password)
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}
