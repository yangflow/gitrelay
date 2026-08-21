import Foundation

nonisolated enum AuthConfig: Codable, Equatable, Sendable {
    case sshAgent
    case sshKey(privateKeyPath: String)
    case httpsToken(keychainTag: String)

    var displayName: String {
        switch self {
        case .sshAgent:   return "SSH Agent"
        case .sshKey:     return "SSH Key"
        case .httpsToken: return "HTTPS Token"
        }
    }
}
