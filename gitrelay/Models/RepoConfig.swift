import Foundation

struct RepoConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var srcURL: String
    var dstURL: String
    var srcAuth: AuthConfig
    var dstAuth: AuthConfig
    var frequency: SyncFrequency
    var createdAt: Date
    var lastSyncedAt: Date?
    var lastSyncError: String?

    init(
        id: UUID = UUID(),
        name: String,
        srcURL: String,
        dstURL: String,
        srcAuth: AuthConfig = .sshAgent,
        dstAuth: AuthConfig = .sshAgent,
        frequency: SyncFrequency = .manual
    ) {
        self.id = id
        self.name = name
        self.srcURL = srcURL
        self.dstURL = dstURL
        self.srcAuth = srcAuth
        self.dstAuth = dstAuth
        self.frequency = frequency
        self.createdAt = Date()
    }
}
