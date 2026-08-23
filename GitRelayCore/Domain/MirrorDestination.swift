import Foundation

nonisolated struct ArchiveDestination: Codable, Equatable, Sendable {
    var directoryPath: String
    var format: ArchiveFormat
    var filenameTemplate: String
    var retentionCount: Int?

    init(
        directoryPath: String,
        format: ArchiveFormat = .tarGz,
        filenameTemplate: String? = nil,
        retentionCount: Int? = nil
    ) {
        self.directoryPath = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.format = format
        let trimmedTemplate = filenameTemplate?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTemplate, !trimmedTemplate.isEmpty {
            self.filenameTemplate = trimmedTemplate
        } else {
            self.filenameTemplate = format.defaultFilenameTemplate
        }
        self.retentionCount = retentionCount.map { max(1, $0) }
    }

    var identity: GitRemoteIdentity? {
        GitRemoteIdentity.filesystemPath(directoryPath)
    }

    func validate() throws {
        guard !directoryPath.isEmpty else {
            throw MirrorDomainError.emptyArchivePath
        }
        guard !filenameTemplate.isEmpty else {
            throw MirrorDomainError.emptyArchiveFilenameTemplate
        }
        guard ArchiveFilenameTemplate.isSafe(filenameTemplate) else {
            throw MirrorDomainError.unsafeArchiveFilenameTemplate
        }
    }
}

nonisolated enum MirrorDestinationLocation: Codable, Equatable, Sendable {
    case git(GitEndpoint)
    case archive(ArchiveDestination)

    var displayLocation: String {
        switch self {
        case .git(let endpoint):
            endpoint.url
        case .archive(let archive):
            archive.directoryPath
        }
    }

    var identity: GitRemoteIdentity? {
        switch self {
        case .git(let endpoint):
            endpoint.identity
        case .archive(let archive):
            archive.identity
        }
    }

    func validate(allowMissingCredentials: Bool = false) throws {
        switch self {
        case .git(let endpoint):
            try endpoint.validate(
                role: .destination,
                allowMissingCredentials: allowMissingCredentials
            )
        case .archive(let archive):
            try archive.validate()
        }
    }
}

nonisolated struct MirrorDestination: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var location: MirrorDestinationLocation
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        location: MirrorDestinationLocation,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.location = location
        self.isEnabled = isEnabled
    }

    static func git(
        id: UUID = UUID(),
        url: String,
        auth: AuthConfig = .sshAgent,
        provider: GitProvider? = nil,
        accountLabel: String? = nil,
        isEnabled: Bool = true
    ) -> MirrorDestination {
        MirrorDestination(
            id: id,
            location: .git(
                GitEndpoint(
                    url: url,
                    auth: auth,
                    provider: provider,
                    accountLabel: accountLabel
                )
            ),
            isEnabled: isEnabled
        )
    }

    static func archive(
        id: UUID = UUID(),
        directoryPath: String,
        format: ArchiveFormat = .tarGz,
        filenameTemplate: String? = nil,
        retentionCount: Int? = nil,
        isEnabled: Bool = true
    ) -> MirrorDestination {
        MirrorDestination(
            id: id,
            location: .archive(
                ArchiveDestination(
                    directoryPath: directoryPath,
                    format: format,
                    filenameTemplate: filenameTemplate,
                    retentionCount: retentionCount
                )
            ),
            isEnabled: isEnabled
        )
    }
}
