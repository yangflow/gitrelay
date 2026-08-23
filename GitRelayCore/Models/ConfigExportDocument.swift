import Foundation

/// Portable configuration snapshot for moving GitRelay between machines.
/// Secrets (HTTPS tokens, Keychain values, private key material) are never included.
nonisolated struct ConfigExportDocument: Codable, Equatable, Sendable {
    static let formatIdentifier = "gitrelay-mirror-plan"
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var exportedAt: Date?
    var mirrors: [ExportedMirrorPlan]
    var providerAccounts: [ExportedProviderAccount]
    var orgSubscriptions: [ExportedOrgSubscription]
    var orgSubscriptionPreferences: OrgSubscriptionPreferences?

    init(
        format: String = formatIdentifier,
        schemaVersion: Int = currentSchemaVersion,
        exportedAt: Date? = Date(),
        mirrors: [ExportedMirrorPlan] = [],
        providerAccounts: [ExportedProviderAccount] = [],
        orgSubscriptions: [ExportedOrgSubscription] = [],
        orgSubscriptionPreferences: OrgSubscriptionPreferences? = nil
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.mirrors = mirrors
        self.providerAccounts = providerAccounts
        self.orgSubscriptions = orgSubscriptions
        self.orgSubscriptionPreferences = orgSubscriptionPreferences
    }
}

nonisolated struct ExportedProviderAccount: Codable, Equatable, Hashable, Sendable {
    var provider: GitProvider
    var label: String
    var host: String?
}

nonisolated struct ExportedOrgSubscription: Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var provider: GitProvider
    var accountLabel: String
    var organizationName: String
    var autoAddEnabled: Bool
    var template: ExportedOrgSubscriptionTemplate
    var lastCheckedAt: Date?

    init(from subscription: OrgSubscription) {
        id = subscription.id
        provider = subscription.provider
        accountLabel = subscription.accountLabel
        organizationName = subscription.organizationName
        autoAddEnabled = subscription.autoAddEnabled
        template = ExportedOrgSubscriptionTemplate(from: subscription.template)
        lastCheckedAt = subscription.lastCheckedAt
    }

    func toOrgSubscription() -> OrgSubscription {
        OrgSubscription(
            id: id,
            provider: provider,
            accountLabel: accountLabel,
            organizationName: organizationName,
            autoAddEnabled: autoAddEnabled,
            template: template.toTemplate(),
            lastCheckedAt: lastCheckedAt
        )
    }
}

/// Org template with machine-local SSH paths stripped.
nonisolated struct ExportedOrgSubscriptionTemplate: Codable, Equatable, Hashable, Sendable {
    var sourceAuthMode: AuthMode
    var sourceKeyPath: String
    var targetURLTemplate: String
    var targetAuthMode: AuthMode
    var targetKeyPath: String
    var namePrefix: String
    var frequency: SyncFrequency
    var targetAutoCreate: Bool
    var targetCreateHost: String
    var targetNamespaceKind: OrgSubscriptionTargetNamespaceKind
    var targetNamespaceOwner: String
    var targetVisibilityPrivate: Bool

    init(from template: OrgSubscriptionTemplate) {
        sourceAuthMode = template.sourceAuthMode
        sourceKeyPath = Self.portableKeyPath(template.sourceKeyPath)
        targetURLTemplate = template.targetURLTemplate
        targetAuthMode = template.targetAuthMode
        targetKeyPath = Self.portableKeyPath(template.targetKeyPath)
        namePrefix = template.namePrefix
        frequency = template.frequency
        targetAutoCreate = template.targetAutoCreate
        targetCreateHost = template.targetCreateHost
        targetNamespaceKind = template.targetNamespaceKind
        targetNamespaceOwner = template.targetNamespaceOwner
        targetVisibilityPrivate = template.targetVisibilityPrivate
    }

    func toTemplate() -> OrgSubscriptionTemplate {
        OrgSubscriptionTemplate(
            sourceAuthMode: sourceAuthMode,
            sourceKeyPath: sourceKeyPath,
            targetURLTemplate: targetURLTemplate,
            targetAuthMode: targetAuthMode,
            targetKeyPath: targetKeyPath,
            namePrefix: namePrefix,
            frequency: frequency,
            targetAutoCreate: targetAutoCreate,
            targetCreateHost: targetCreateHost,
            targetNamespaceKind: targetNamespaceKind,
            targetNamespaceOwner: targetNamespaceOwner,
            targetVisibilityPrivate: targetVisibilityPrivate
        )
    }

    private static func portableKeyPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || ExportedAuth.isMachineLocalPath(trimmed) {
            return ""
        }
        return trimmed
    }
}

nonisolated struct ExportedGitEndpoint: Codable, Equatable, Sendable {
    var url: String
    var auth: ExportedAuth
    var provider: GitProvider?
    var accountLabel: String?

    init(from endpoint: GitEndpoint) {
        url = endpoint.url
        auth = ExportedAuth.from(endpoint.auth)
        provider = endpoint.provider
        accountLabel = endpoint.accountLabel
    }

    func toGitEndpoint(keychainTag: String) -> GitEndpoint {
        GitEndpoint(
            url: url,
            auth: auth.toAuthConfig(keychainTag: keychainTag),
            provider: provider,
            accountLabel: accountLabel
        )
    }
}

nonisolated enum ExportedMirrorDestinationLocation: Codable, Equatable, Sendable {
    case git(ExportedGitEndpoint)
    case archive(ArchiveDestination)

    init(from location: MirrorDestinationLocation) {
        switch location {
        case .git(let endpoint):
            self = .git(ExportedGitEndpoint(from: endpoint))
        case .archive(let archive):
            // Archive paths are intentionally retained so the importing user can remap them.
            self = .archive(archive)
        }
    }

    func toLocation(
        mirrorID: UUID,
        destinationID: UUID,
        credentialNamespace: UUID
    ) -> MirrorDestinationLocation {
        switch self {
        case .git(let endpoint):
            let tag = MirrorCredentialTags.destinationTokenTag(
                mirrorID: mirrorID,
                destinationID: destinationID,
                namespace: credentialNamespace
            )
            return .git(endpoint.toGitEndpoint(keychainTag: tag))
        case .archive(let archive):
            return .archive(archive)
        }
    }
}

nonisolated struct ExportedMirrorDestination: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var location: ExportedMirrorDestinationLocation
    var isEnabled: Bool

    init(from destination: MirrorDestination) {
        id = destination.id
        location = ExportedMirrorDestinationLocation(from: destination.location)
        isEnabled = destination.isEnabled
    }

    func toDestination(mirrorID: UUID, credentialNamespace: UUID) -> MirrorDestination {
        MirrorDestination(
            id: id,
            location: location.toLocation(
                mirrorID: mirrorID,
                destinationID: id,
                credentialNamespace: credentialNamespace
            ),
            isEnabled: isEnabled
        )
    }
}

nonisolated struct ExportedMirrorPlan: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var source: ExportedGitEndpoint
    var destinations: [ExportedMirrorDestination]
    var policy: MirrorPolicy
    var labels: [String]
    var createdAt: Date
    var isSchedulePaused: Bool

    init(from plan: MirrorPlan) {
        id = plan.id
        name = plan.name
        source = ExportedGitEndpoint(from: plan.source)
        destinations = plan.destinations.map(ExportedMirrorDestination.init(from:))
        policy = plan.policy
        labels = plan.labels
        createdAt = plan.createdAt
        isSchedulePaused = plan.isSchedulePaused
    }

    func toMirrorPlan() -> MirrorPlan {
        // Portable exports never carry credentials. Give every import a fresh
        // namespace so an old token for the same mirror UUID cannot silently be
        // reused against a different host supplied by the imported document.
        let credentialNamespace = UUID()
        return MirrorPlan(
            id: id,
            name: name,
            source: source.toGitEndpoint(
                keychainTag: MirrorCredentialTags.sourceTokenTag(
                    mirrorID: id,
                    namespace: credentialNamespace
                )
            ),
            destinations: destinations.map {
                $0.toDestination(mirrorID: id, credentialNamespace: credentialNamespace)
            },
            policy: policy,
            labels: labels,
            createdAt: createdAt,
            isSchedulePaused: isSchedulePaused
        )
    }
}

nonisolated enum MirrorCredentialTags {
    static func sourceTokenTag(mirrorID: UUID, namespace: UUID? = nil) -> String {
        let suffix = namespace.map { "-import-\($0.uuidString)" } ?? ""
        return "\(mirrorID.uuidString)\(suffix)-src"
    }

    static func destinationTokenTag(
        mirrorID: UUID,
        destinationID: UUID,
        namespace: UUID? = nil
    ) -> String {
        let suffix = namespace.map { "-import-\($0.uuidString)" } ?? ""
        return "\(mirrorID.uuidString)\(suffix)-target-\(destinationID.uuidString)"
    }
}
