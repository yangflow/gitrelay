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
    var lastSuccessfulSyncedAt: Date?
    var lastSyncError: String?
    var consecutiveFailureCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        srcURL: String,
        dstURL: String,
        srcAuth: AuthConfig = .sshAgent,
        dstAuth: AuthConfig = .sshAgent,
        frequency: SyncFrequency = .manual,
        destructivePushPolicy: DestructivePushPolicy = .strict,
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        lastSuccessfulSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        consecutiveFailureCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.srcURL = srcURL
        self.dstURL = dstURL
        self.srcAuth = srcAuth
        self.dstAuth = dstAuth
        self.frequency = frequency
        self.destructivePushPolicy = destructivePushPolicy
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
        self.lastSuccessfulSyncedAt = lastSuccessfulSyncedAt
        self.lastSyncError = lastSyncError
        self.consecutiveFailureCount = max(0, consecutiveFailureCount)
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
        case lastSuccessfulSyncedAt
        case lastSyncError
        case consecutiveFailureCount
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
        let decodedLastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        let decodedLastSyncError = try container.decodeIfPresent(String.self, forKey: .lastSyncError)
        lastSyncedAt = decodedLastSyncedAt
        lastSyncError = decodedLastSyncError
        lastSuccessfulSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncedAt)
            ?? (decodedLastSyncError == nil ? decodedLastSyncedAt : nil)
        consecutiveFailureCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .consecutiveFailureCount)
                ?? (decodedLastSyncError == nil ? 0 : 1)
        )
    }

    mutating func recordSyncResult(at date: Date = .now, error: String?) {
        lastSyncedAt = date
        lastSyncError = error

        if error == nil {
            lastSuccessfulSyncedAt = date
            consecutiveFailureCount = 0
        } else {
            consecutiveFailureCount = max(0, consecutiveFailureCount) + 1
        }
    }
}
