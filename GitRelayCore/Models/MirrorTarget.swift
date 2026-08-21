import Foundation

nonisolated struct MirrorTarget: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: MirrorTargetKind
    var url: String
    var auth: AuthConfig
    var enabled: Bool
    var filesystemPath: String?
    var archiveFormat: ArchiveFormat?
    var filenameTemplate: String?
    var retentionCount: Int?

    init(
        id: UUID = UUID(),
        kind: MirrorTargetKind = .gitRemote,
        url: String = "",
        auth: AuthConfig = .sshAgent,
        enabled: Bool = true,
        filesystemPath: String? = nil,
        archiveFormat: ArchiveFormat? = nil,
        filenameTemplate: String? = nil,
        retentionCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.auth = auth
        self.enabled = enabled
        self.filesystemPath = filesystemPath
        self.archiveFormat = archiveFormat
        self.filenameTemplate = filenameTemplate
        self.retentionCount = retentionCount
    }

    /// Convenience for git-remote targets.
    init(
        id: UUID = UUID(),
        url: String,
        auth: AuthConfig = .sshAgent,
        enabled: Bool = true
    ) {
        self.init(
            id: id,
            kind: .gitRemote,
            url: url,
            auth: auth,
            enabled: enabled
        )
    }

    var displayLabel: String {
        switch kind {
        case .gitRemote:
            return url
        case .filesystem:
            return filesystemPath ?? url
        }
    }

    var resolvedArchiveFormat: ArchiveFormat {
        archiveFormat ?? .tarGz
    }

    func resolvedFilenameTemplate() -> String {
        if let filenameTemplate, !filenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return filenameTemplate
        }
        return resolvedArchiveFormat.defaultFilenameTemplate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case url
        case auth
        case enabled
        case filesystemPath
        case archiveFormat
        case filenameTemplate
        case retentionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(MirrorTargetKind.self, forKey: .kind) ?? .gitRemote
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        auth = try container.decodeIfPresent(AuthConfig.self, forKey: .auth) ?? .sshAgent
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        filesystemPath = try container.decodeIfPresent(String.self, forKey: .filesystemPath)
        archiveFormat = try container.decodeIfPresent(ArchiveFormat.self, forKey: .archiveFormat)
        filenameTemplate = try container.decodeIfPresent(String.self, forKey: .filenameTemplate)
        retentionCount = try container.decodeIfPresent(Int.self, forKey: .retentionCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if kind != .gitRemote {
            try container.encode(kind, forKey: .kind)
        }
        if !url.isEmpty {
            try container.encode(url, forKey: .url)
        }
        if auth != .sshAgent {
            try container.encode(auth, forKey: .auth)
        }
        if !enabled {
            try container.encode(enabled, forKey: .enabled)
        }
        try container.encodeIfPresent(filesystemPath, forKey: .filesystemPath)
        try container.encodeIfPresent(archiveFormat, forKey: .archiveFormat)
        try container.encodeIfPresent(filenameTemplate, forKey: .filenameTemplate)
        if let retentionCount {
            try container.encode(retentionCount, forKey: .retentionCount)
        }
    }
}
