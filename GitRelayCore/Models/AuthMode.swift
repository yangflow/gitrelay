import Foundation

enum AuthMode: String, CaseIterable, Identifiable, Codable {
    case sshAgent   = "SSH Agent"
    case sshKey     = "SSH Key"
    case httpsToken = "HTTPS Token"

    var id: String { rawValue }
}
