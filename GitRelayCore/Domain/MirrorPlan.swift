import Foundation

nonisolated struct MirrorPlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var source: GitEndpoint
    var destinations: [MirrorDestination]
    var policy: MirrorPolicy
    var labels: [String]
    var createdAt: Date
    var isSchedulePaused: Bool

    init(
        id: UUID = UUID(),
        name: String,
        source: GitEndpoint,
        destinations: [MirrorDestination],
        policy: MirrorPolicy = MirrorPolicy(),
        labels: [String] = [],
        createdAt: Date = Date(),
        isSchedulePaused: Bool = false
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.destinations = destinations
        self.policy = policy
        self.labels = Self.normalizedLabels(labels)
        self.createdAt = createdAt
        self.isSchedulePaused = isSchedulePaused
    }

    var enabledDestinations: [MirrorDestination] {
        destinations.filter(\.isEnabled)
    }

    /// Validates a plan for execution by default. Persistence may retain an
    /// otherwise valid plan whose machine-local SSH key must be selected again.
    func validated(allowMissingCredentials: Bool = false) throws -> MirrorPlan {
        guard !name.isEmpty else {
            throw MirrorDomainError.emptyName
        }
        try source.validate(
            role: .source,
            allowMissingCredentials: allowMissingCredentials
        )
        guard !destinations.isEmpty else {
            throw MirrorDomainError.noDestinations
        }
        guard !enabledDestinations.isEmpty else {
            throw MirrorDomainError.noEnabledDestinations
        }

        var destinationIDs = Set<UUID>()
        var destinationIdentities = Set<GitRemoteIdentity>()
        for destination in destinations {
            guard destinationIDs.insert(destination.id).inserted else {
                throw MirrorDomainError.duplicateDestinationID(destination.id)
            }
            try destination.location.validate(
                allowMissingCredentials: allowMissingCredentials
            )
            if let identity = destination.location.identity,
               !destinationIdentities.insert(identity).inserted {
                throw MirrorDomainError.duplicateDestination(identity.value)
            }
            if let sourceIdentity = source.identity,
               destination.location.identity == sourceIdentity {
                throw MirrorDomainError.sourceMatchesDestination
            }
        }
        return self
    }

    static func normalizedLabels(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            let key = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }
}

nonisolated enum MirrorDomainError: Error, Equatable, LocalizedError, Sendable {
    case emptyName
    case emptyEndpoint(MirrorEndpointRole)
    case emptySSHKeyPath(MirrorEndpointRole)
    case emptyCredentialReference(MirrorEndpointRole)
    case emptyArchivePath
    case emptyArchiveFilenameTemplate
    case unsafeArchiveFilenameTemplate
    case noDestinations
    case noEnabledDestinations
    case duplicateDestinationID(UUID)
    case duplicateDestination(String)
    case sourceMatchesDestination

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Mirror name is required."
        case .emptyEndpoint(let role):
            "The \(role.rawValue) location is required."
        case .emptySSHKeyPath(let role):
            "The \(role.rawValue) SSH key path is required."
        case .emptyCredentialReference(let role):
            "The \(role.rawValue) credential reference is required."
        case .emptyArchivePath:
            "The archive directory is required."
        case .emptyArchiveFilenameTemplate:
            "The archive filename template is required."
        case .unsafeArchiveFilenameTemplate:
            "The archive filename template must be a filename, not a path."
        case .noDestinations:
            "At least one destination is required."
        case .noEnabledDestinations:
            "At least one destination must be enabled."
        case .duplicateDestinationID:
            "Destination identifiers must be unique."
        case .duplicateDestination(let value):
            "The destination \(value) is included more than once."
        case .sourceMatchesDestination:
            "The source and destination must be different."
        }
    }
}
