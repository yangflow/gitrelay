import Foundation

struct RepoConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var srcURL: String
    var dstURL: String
    var srcAuth: AuthConfig
    var dstAuth: AuthConfig
    var frequency: SyncFrequency
    var destructivePushPolicy: DestructivePushPolicy
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
        frequency: SyncFrequency = .manual,
        destructivePushPolicy: DestructivePushPolicy = .strict
    ) {
        self.id = id
        self.name = name
        self.srcURL = srcURL
        self.dstURL = dstURL
        self.srcAuth = srcAuth
        self.dstAuth = dstAuth
        self.frequency = frequency
        self.destructivePushPolicy = destructivePushPolicy
        self.createdAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case srcURL
        case dstURL
        case srcAuth
        case dstAuth
        case frequency
        case destructivePushPolicy
        case createdAt
        case lastSyncedAt
        case lastSyncError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        srcURL = try container.decode(String.self, forKey: .srcURL)
        dstURL = try container.decode(String.self, forKey: .dstURL)
        srcAuth = try container.decode(AuthConfig.self, forKey: .srcAuth)
        dstAuth = try container.decode(AuthConfig.self, forKey: .dstAuth)
        frequency = try container.decode(SyncFrequency.self, forKey: .frequency)
        destructivePushPolicy = try container.decodeIfPresent(
            DestructivePushPolicy.self,
            forKey: .destructivePushPolicy
        ) ?? .auto
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        lastSyncError = try container.decodeIfPresent(String.self, forKey: .lastSyncError)
    }
}
