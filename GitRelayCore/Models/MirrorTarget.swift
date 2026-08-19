import Foundation

struct MirrorTarget: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    var auth: AuthConfig
    var enabled: Bool

    init(
        id: UUID = UUID(),
        url: String,
        auth: AuthConfig = .sshAgent,
        enabled: Bool = true
    ) {
        self.id = id
        self.url = url
        self.auth = auth
        self.enabled = enabled
    }
}
