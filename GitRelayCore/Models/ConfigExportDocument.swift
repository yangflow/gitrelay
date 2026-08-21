import Foundation

/// Portable configuration snapshot for moving GitRelay between machines.
/// Secrets (HTTPS tokens, Keychain values, private key material) are never included.
nonisolated struct ConfigExportDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date?
    var repos: [ExportedRepo]
    var providerAccounts: [ExportedProviderAccount]
    var orgSubscriptions: [ExportedOrgSubscription]
    var orgSubscriptionPreferences: OrgSubscriptionPreferences?

    init(
        schemaVersion: Int = currentSchemaVersion,
        exportedAt: Date? = Date(),
        repos: [ExportedRepo] = [],
        providerAccounts: [ExportedProviderAccount] = [],
        orgSubscriptions: [ExportedOrgSubscription] = [],
        orgSubscriptionPreferences: OrgSubscriptionPreferences? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.repos = repos
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

nonisolated struct ExportedMirrorTarget: Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var kind: MirrorTargetKind
    var url: String
    var auth: ExportedAuth
    var enabled: Bool
    var filesystemPath: String?
    var archiveFormat: ArchiveFormat?
    var filenameTemplate: String?
    var retentionCount: Int?

    init(from target: MirrorTarget) {
        id = target.id
        kind = target.kind
        url = target.url
        auth = ExportedAuth.from(target.auth)
        enabled = target.enabled
        // Filesystem archive dirs are machine-local; keep the path so the user can remap,
        // but never treat it as a credential.
        filesystemPath = target.filesystemPath
        archiveFormat = target.archiveFormat
        filenameTemplate = target.filenameTemplate
        retentionCount = target.retentionCount
    }

    func toMirrorTarget(repoID: UUID) -> MirrorTarget {
        let tag = RepoCredentialTags.targetTokenTag(repoID: repoID, targetID: id)
        return MirrorTarget(
            id: id,
            kind: kind,
            url: url,
            auth: auth.toAuthConfig(keychainTag: tag),
            enabled: enabled,
            filesystemPath: filesystemPath,
            archiveFormat: archiveFormat,
            filenameTemplate: filenameTemplate,
            retentionCount: retentionCount
        )
    }
}

nonisolated struct ExportedRepo: Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var srcURL: String
    var targets: [ExportedMirrorTarget]
    var srcAuth: ExportedAuth
    var frequency: SyncFrequency
    var destructivePushPolicy: DestructivePushPolicy
    var defaultBranch: String
    var createdAt: Date
    var tags: [String]
    var mirrorReleases: Bool
    var lfsMirrorMode: LFSMirrorMode
    var depth: Int?
    var refSpecs: [String]
    var webhookEnabled: Bool

    init(from repo: RepoConfig) {
        id = repo.id
        name = repo.name
        srcURL = repo.srcURL
        targets = repo.targets.map(ExportedMirrorTarget.init(from:))
        srcAuth = ExportedAuth.from(repo.srcAuth)
        frequency = repo.frequency
        destructivePushPolicy = repo.destructivePushPolicy
        defaultBranch = repo.defaultBranch
        createdAt = repo.createdAt
        tags = repo.tags
        mirrorReleases = repo.mirrorReleases
        lfsMirrorMode = repo.lfsMirrorMode
        depth = repo.depth
        refSpecs = repo.refSpecs
        webhookEnabled = repo.webhookEnabled
    }

    func toRepoConfig(probe: CredentialProbe) -> RepoConfig {
        let srcTag = RepoCredentialTags.sourceTokenTag(repoID: id)
        let mirrorTargets = targets.map { $0.toMirrorTarget(repoID: id) }
        var repo = RepoConfig(
            id: id,
            name: name,
            srcURL: srcURL,
            targets: mirrorTargets,
            srcAuth: srcAuth.toAuthConfig(keychainTag: srcTag),
            frequency: frequency,
            destructivePushPolicy: destructivePushPolicy,
            defaultBranch: defaultBranch,
            createdAt: createdAt,
            tags: tags,
            mirrorReleases: mirrorReleases,
            lfsMirrorMode: lfsMirrorMode,
            depth: depth,
            refSpecs: refSpecs,
            webhookEnabled: webhookEnabled
        )
        repo.needsCredentials = RepoCredentialGate.needsCredentials(for: repo, probe: probe)
        return repo
    }
}

nonisolated enum RepoCredentialTags {
    static func sourceTokenTag(repoID: UUID) -> String {
        "\(repoID.uuidString)-src"
    }

    static func targetTokenTag(repoID: UUID, targetID: UUID) -> String {
        "\(repoID.uuidString)-target-\(targetID.uuidString)"
    }
}
