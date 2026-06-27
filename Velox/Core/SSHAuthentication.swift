import Foundation
@preconcurrency import Citadel
@preconcurrency import Crypto

/// Authentication choices exposed by Velox's UI and persistence layers.
enum SSHAuthentication: Sendable {
    case password(String)
    case rsaPrivateKey(Data)
    case ed25519PrivateKey(Data, passphrase: Data? = nil)

    func makeCitadelMethod(username: String) throws -> SSHAuthenticationMethod {
        switch self {
        case .password(let password):
            return .passwordBased(username: username, password: password)
        case .rsaPrivateKey(let keyData):
            return .rsa(username: username, privateKey: try Insecure.RSA.PrivateKey(sshRsa: keyData))
        case .ed25519PrivateKey(let keyData, let passphrase):
            return .ed25519(
                username: username,
                privateKey: try Curve25519.Signing.PrivateKey(
                    sshEd25519: keyData,
                    decryptionKey: passphrase
                )
            )
        }
    }
}
