import Foundation
import SwiftUI
import Observation

struct MirrorTargetDraft: Identifiable, Equatable {
    let id: UUID
    var kind: MirrorTargetKind
    var url: String
    var authMode: AuthMode
    var keyPath: String
    var token: String
    var enabled: Bool
    let preservedAuth: AuthConfig?
    var filesystemPath: String
    var archiveFormat: ArchiveFormat
    var filenameTemplate: String
    var retentionCount: String

    init(
        id: UUID = UUID(),
        kind: MirrorTargetKind = .gitRemote,
        url: String = "",
        authMode: AuthMode = .sshAgent,
        keyPath: String = "",
        token: String = "",
        enabled: Bool = true,
        preservedAuth: AuthConfig? = nil,
        filesystemPath: String = "",
        archiveFormat: ArchiveFormat = .tarGz,
        filenameTemplate: String = "",
        retentionCount: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.authMode = authMode
        self.keyPath = keyPath
        self.token = token
        self.enabled = enabled
        self.preservedAuth = preservedAuth
        self.filesystemPath = filesystemPath
        self.archiveFormat = archiveFormat
        self.filenameTemplate = filenameTemplate
        self.retentionCount = retentionCount
    }

    init(from target: MirrorTarget) {
        self.id = target.id
        self.kind = target.kind
        self.url = target.url
        self.enabled = target.enabled
        self.preservedAuth = target.auth
        self.keyPath = ""
        self.token = ""
        self.filesystemPath = target.filesystemPath ?? ""
        self.archiveFormat = target.resolvedArchiveFormat
        self.filenameTemplate = target.filenameTemplate ?? ""
        self.retentionCount = target.retentionCount.map(String.init) ?? ""
        switch target.auth {
        case .sshAgent:
            self.authMode = .sshAgent
        case .sshKey(let path):
            self.authMode = .sshKey
            self.keyPath = path
        case .httpsToken:
            self.authMode = .httpsToken
        }
    }
}

@MainActor
@Observable
final class AddEditRepoViewModel {
    var name: String           = ""
    var srcURL: String         = "" {
        didSet {
            guard srcURL != oldValue else { return }
            applySourceURLInference()
        }
    }
    var targets: [MirrorTargetDraft] = [MirrorTargetDraft()]
    var srcAuthMode: AuthMode  = .sshAgent
    var srcKeyPath: String     = ""
    var srcToken: String       = ""
    var frequency: SyncFrequency = .manual
    var destructivePushPolicy: DestructivePushPolicy = .strict
    var defaultBranch: String = "main"
    var tags: [String] = []
    var mirrorReleases: Bool = false
    var lfsMirrorMode: LFSMirrorMode = .auto
    var depthText: String = ""
    var refSpecsText: String = RepoConfig.defaultRefSpecs.joined(separator: "\n")
    var webhookEnabled: Bool = false
    var registerWebhookOnSave: Bool = false
    var webhookRegistrationToken: String = ""
    var webhookRegistrationMessage: String?
    var webhookScopeValidation: TokenScopeValidation?

    /// When false, the sheet shows the quiet two-field basics step.
    var showsMoreOptions: Bool = false

    /// Once the user edits name in More Options, stop auto-replacing from the source URL.
    private(set) var nameIsUserOverride: Bool = false

    var nameError: String?
    var srcError: String?
    var depthError: String?
    var targetErrors: [UUID: String] = [:]

    let editingID: UUID?

    private let createdAt: Date?
    private let lastSyncedAt: Date?
    private let lastSuccessfulSyncedAt: Date?
    private let lastSyncError: String?
    private let consecutiveFailureCount: Int
    private let dailySyncOutcomes: [String: SyncDayOutcome]
    private let lastVerifiedAt: Date?
    private let divergedDetail: String?
    private let defaults: UserDefaults
    /// HTTPS / token default used when the source URL is http(s).
    private let preferredHTTPSAuthMode: AuthMode

    init(
        editing repo: RepoConfig? = nil,
        prefill: RepoSourceDropPrefill? = nil,
        defaults: UserDefaults = .standard
    ) {
        editingID = repo?.id
        createdAt = repo?.createdAt
        lastSyncedAt = repo?.lastSyncedAt
        lastSuccessfulSyncedAt = repo?.lastSuccessfulSyncedAt
        lastSyncError = repo?.lastSyncError
        consecutiveFailureCount = repo?.consecutiveFailureCount ?? 0
        dailySyncOutcomes = repo?.dailySyncOutcomes ?? [:]
        lastVerifiedAt = repo?.lastVerifiedAt
        divergedDetail = repo?.divergedDetail
        self.defaults = defaults

        let lastUsed = LastUsedAuthMode.load(from: defaults)
        // HTTPS remotes use the app's existing token auth mode (not a new mode).
        preferredHTTPSAuthMode = .httpsToken

        if let repo {
            // Saved name is authoritative — don't clobber it when the URL is edited.
            nameIsUserOverride = true
            name      = repo.name
            srcURL    = repo.srcURL
            targets   = repo.targets.map { MirrorTargetDraft(from: $0) }
            frequency = repo.frequency
            destructivePushPolicy = repo.destructivePushPolicy
            defaultBranch = repo.defaultBranch
            tags = repo.tags
            mirrorReleases = repo.mirrorReleases
            lfsMirrorMode = repo.lfsMirrorMode
            depthText = repo.depth.map(String.init) ?? ""
            refSpecsText = repo.resolvedRefSpecs.joined(separator: "\n")
            webhookEnabled = repo.webhookEnabled
            populate(auth: repo.srcAuth, mode: &srcAuthMode, keyPath: &srcKeyPath, token: &srcToken)
            showsMoreOptions = false
        } else {
            let defaultAuth = lastUsed ?? .sshAgent
            srcAuthMode = defaultAuth
            targets = [MirrorTargetDraft(authMode: defaultAuth)]
            if let prefill {
                applyPrefill(prefill)
            }
        }
    }

    func applyPrefill(_ prefill: RepoSourceDropPrefill) {
        srcURL = prefill.srcURL
        // didSet does not run during init assignment chains reliably for the first
        // write in all paths — apply inference explicitly after setting the URL.
        applySourceURLInference()
        if !nameIsUserOverride,
           let inferred = prefill.inferredName,
           !inferred.isEmpty {
            name = inferred
        }
        if let dstURL = prefill.dstURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dstURL.isEmpty {
            if targets.isEmpty {
                targets = [MirrorTargetDraft(url: dstURL)]
            } else {
                targets[0].url = dstURL
            }
        }
    }

    /// Records a user edit to the display name (More Options). Further source URL
    /// changes will not overwrite it.
    func updateName(_ newValue: String) {
        name = newValue
        nameIsUserOverride = true
    }

    /// Opens the optional more-options step. Does not validate — Save / Add and Start Syncing own validation.
    func openMoreOptions() {
        showsMoreOptions = true
    }

    func backToBasics() {
        showsMoreOptions = false
    }

    /// Secondary caption under the source URL on the basics step, e.g. "SSH Agent · my-project".
    var basicsInferenceCaption: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = srcURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty || !trimmedName.isEmpty else { return nil }
        if trimmedName.isEmpty {
            return srcAuthMode.rawValue
        }
        return "\(srcAuthMode.rawValue) · \(trimmedName)"
    }

    /// Primary target location shown on the basics step (Git URL or archive path).
    var primaryTargetLocation: String {
        get {
            guard let target = targets.first else { return "" }
            switch target.kind {
            case .gitRemote:
                return target.url
            case .filesystem:
                return target.filesystemPath
            }
        }
        set {
            guard !targets.isEmpty else { return }
            switch targets[0].kind {
            case .gitRemote:
                targets[0].url = newValue
            case .filesystem:
                targets[0].filesystemPath = newValue
            }
        }
    }

    var primaryTargetUsesFilesystemPath: Bool {
        targets.first?.kind == .filesystem
    }

    /// Derives a repo display name from a source URL or local path (strips `.git`).
    nonisolated static func inferredRepoName(fromSourceURL url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let remoteName = GitRemoteRepoPath.parse(from: trimmed)?.name, !remoteName.isEmpty {
            return remoteName
        }

        let path: String
        if trimmed.hasPrefix("file://"), let fileURL = URL(string: trimmed) {
            path = fileURL.standardizedFileURL.path
        } else if trimmed.hasPrefix("~") {
            path = NSString(string: trimmed).expandingTildeInPath
        } else {
            path = trimmed
        }

        let fileURL = URL(fileURLWithPath: path, isDirectory: true)
        if fileURL.lastPathComponent == ".git" {
            let parent = fileURL.deletingLastPathComponent().lastPathComponent
            return parent.isEmpty ? nil : parent
        }
        var name = fileURL.lastPathComponent
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        return name.isEmpty ? nil : name
    }

    /// Infers auth from the source URL scheme. SSH → SSH Agent; http(s) → HTTPS Token.
    nonisolated static func inferredAuthMode(
        fromSourceURL url: String,
        httpsDefault: AuthMode = .httpsToken
    ) -> AuthMode? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("git@") || trimmed.lowercased().hasPrefix("ssh://") {
            return .sshAgent
        }
        if let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() {
            if scheme == "https" || scheme == "http" {
                return httpsDefault
            }
        }
        return nil
    }

    /// Re-applies name/auth inference from the current source URL.
    func applySourceURLInference() {
        if let inferredAuth = Self.inferredAuthMode(
            fromSourceURL: srcURL,
            httpsDefault: preferredHTTPSAuthMode
        ) {
            srcAuthMode = inferredAuth
        }
        guard !nameIsUserOverride else { return }
        if let inferred = Self.inferredRepoName(fromSourceURL: srcURL) {
            name = inferred
        }
    }

    var partialSyncWarning: String? {
        let depth = parsedDepth()
        let refSpecs = parsedRefSpecs()
        let isShallow = depth != nil
        let isCustomRefs = !RepoConfig.refSpecsEqual(refSpecs, RepoConfig.defaultRefSpecs)
        guard isShallow || isCustomRefs else { return nil }
        if isShallow {
            return String.loc("A shallow clone cannot perform a complete push --mirror. Only the selected refs will sync, so this is not a complete backup.")
        }
        return String.loc("Custom ref filters are set. Only the selected refs will sync, so this is not a complete backup.")
    }

    var isValid: Bool {
        nameError == nil && srcError == nil && depthError == nil && targetErrors.isEmpty
    }

    /// Validates name, source, and targets only.
    @discardableResult
    func validateBasics() -> Bool {
        normalizeSourceURLIfNeeded()
        applySourceURLInference()

        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? String.loc("Enter a name") : nil
        srcError = isValidSourceURL(srcURL) ? nil : String.loc("Enter a valid Git URL")

        targetErrors = [:]
        guard !targets.isEmpty else {
            return false
        }

        for target in targets {
            switch target.kind {
            case .gitRemote:
                let trimmed = target.url.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    targetErrors[target.id] = String.loc("Enter a valid Git URL")
                } else if !isValidGitURL(trimmed) {
                    targetErrors[target.id] = String.loc("Enter a valid Git URL")
                }
            case .filesystem:
                let trimmed = target.filesystemPath.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    targetErrors[target.id] = String.loc("Choose an archive directory")
                }
                if let retention = parsedRetentionCount(for: target), retention < 1 {
                    targetErrors[target.id] = String.loc("The number to keep must be a positive integer")
                }
            }
        }

        if targets.filter(isTargetConfigured).allSatisfy({ !$0.enabled }) {
            if targetErrors.isEmpty {
                targetErrors[targets[0].id] = String.loc("Enable at least one target")
            }
        }

        return nameError == nil && srcError == nil && targetErrors.isEmpty
    }

    @discardableResult
    func validate() -> Bool {
        let basicsOK = validateBasics()
        depthError = validateDepthText()
        return basicsOK && depthError == nil
    }

    func addTarget() {
        targets.append(MirrorTargetDraft())
    }

    func removeTarget(id: UUID) {
        guard targets.count > 1 else { return }
        targets.removeAll { $0.id == id }
        targetErrors.removeValue(forKey: id)
    }

    func buildRepoConfig() -> RepoConfig {
        let id = editingID ?? UUID()
        let mirrorTargets = targets.map { draft in
            buildMirrorTarget(draft: draft, repoID: id)
        }
        return RepoConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            srcURL: srcURL.trimmingCharacters(in: .whitespaces),
            targets: mirrorTargets,
            srcAuth: buildAuth(mode: srcAuthMode, keyPath: srcKeyPath, token: srcToken, repoID: id, side: "src"),
            frequency: frequency,
            destructivePushPolicy: destructivePushPolicy,
            defaultBranch: defaultBranch,
            createdAt: createdAt ?? Date(),
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: lastSyncError,
            consecutiveFailureCount: consecutiveFailureCount,
            dailySyncOutcomes: dailySyncOutcomes,
            lastVerifiedAt: lastVerifiedAt,
            divergedDetail: divergedDetail,
            tags: RepoTagGrouping.normalizedTags(tags),
            mirrorReleases: mirrorReleases,
            lfsMirrorMode: lfsMirrorMode,
            depth: parsedDepth(),
            refSpecs: parsedRefSpecs(),
            webhookEnabled: webhookEnabled
        )
    }

    func saveTokensToKeychain(repoID: UUID) {
        if srcAuthMode == .httpsToken, !srcToken.isEmpty {
            try? KeychainService.saveToken(srcToken, tag: keychainTag(repoID: repoID, side: "src"))
        }
        for target in targets where target.kind == .gitRemote && target.authMode == .httpsToken && !target.token.isEmpty {
            try? KeychainService.saveToken(
                target.token,
                tag: keychainTag(repoID: repoID, targetID: target.id)
            )
        }
        if webhookEnabled {
            _ = try? WebhookSecretStore.ensureSecret(repoID: repoID)
        }
    }

    func rememberLastUsedAuthMode() {
        LastUsedAuthMode.save(srcAuthMode, to: defaults)
    }

    // MARK: - Private

    private func validateDepthText() -> String? {
        let trimmed = depthText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else {
            return String.loc("Depth must be a positive integer")
        }
        return nil
    }

    private func parsedDepth() -> Int? {
        let trimmed = depthText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func parsedRefSpecs() -> [String] {
        let lines = refSpecsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let normalized = RepoConfig.normalizedRefSpecs(lines)
        return normalized.isEmpty ? RepoConfig.defaultRefSpecs : normalized
    }

    private func isTargetConfigured(_ target: MirrorTargetDraft) -> Bool {
        switch target.kind {
        case .gitRemote:
            return isValidGitURL(target.url)
        case .filesystem:
            return !target.filesystemPath.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func parsedRetentionCount(for target: MirrorTargetDraft) -> Int? {
        let trimmed = target.retentionCount.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private func buildMirrorTarget(draft: MirrorTargetDraft, repoID: UUID) -> MirrorTarget {
        switch draft.kind {
        case .gitRemote:
            return MirrorTarget(
                id: draft.id,
                kind: .gitRemote,
                url: draft.url.trimmingCharacters(in: .whitespaces),
                auth: buildAuth(
                    draft: draft,
                    repoID: repoID,
                    targetID: draft.id
                ),
                enabled: draft.enabled
            )
        case .filesystem:
            let template = draft.filenameTemplate.trimmingCharacters(in: .whitespaces)
            return MirrorTarget(
                id: draft.id,
                kind: .filesystem,
                auth: .sshAgent,
                enabled: draft.enabled,
                filesystemPath: draft.filesystemPath.trimmingCharacters(in: .whitespaces),
                archiveFormat: draft.archiveFormat,
                filenameTemplate: template.isEmpty ? nil : template,
                retentionCount: parsedRetentionCount(for: draft)
            )
        }
    }

    private func normalizeSourceURLIfNeeded() {
        let trimmed = srcURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let parsed = RepoSourceDropParser.parse(trimmed) {
            srcURL = parsed.srcURL
        }
    }

    private func isValidSourceURL(_ url: String) -> Bool {
        if isValidGitURL(url) { return true }
        return RepoSourceDropParser.isLocalGitPath(url)
    }

    private func isValidGitURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("git@") { return true }
        if let u = URL(string: trimmed), let scheme = u.scheme?.lowercased() {
            return scheme == "https" || scheme == "http" || scheme == "ssh"
        }
        return false
    }

    private func populate(auth: AuthConfig, mode: inout AuthMode, keyPath: inout String, token: inout String) {
        switch auth {
        case .sshAgent:         mode = .sshAgent
        case .sshKey(let path): mode = .sshKey;     keyPath = path
        case .httpsToken:       mode = .httpsToken
        }
    }

    private func buildAuth(
        draft: MirrorTargetDraft,
        repoID: UUID,
        targetID: UUID
    ) -> AuthConfig {
        if draft.authMode == .httpsToken,
           let preserved = draft.preservedAuth,
           case .httpsToken = preserved {
            return preserved
        }
        return buildAuth(
            mode: draft.authMode,
            keyPath: draft.keyPath,
            token: draft.token,
            repoID: repoID,
            side: "target-\(targetID.uuidString)"
        )
    }

    private func buildAuth(mode: AuthMode, keyPath: String, token: String, repoID: UUID, side: String) -> AuthConfig {
        switch mode {
        case .sshAgent:   .sshAgent
        case .sshKey:     .sshKey(privateKeyPath: keyPath)
        case .httpsToken: .httpsToken(keychainTag: keychainTag(repoID: repoID, side: side))
        }
    }

    private func keychainTag(repoID: UUID, side: String) -> String {
        "\(repoID.uuidString)-\(side)"
    }

    private func keychainTag(repoID: UUID, targetID: UUID) -> String {
        keychainTag(repoID: repoID, side: "target-\(targetID.uuidString)")
    }

    /// Git-remote targets whose host changed compared to the saved configuration.
    func gitRemoteTargetHostChanges(comparedTo original: RepoConfig) -> [(originalURL: String, newURL: String)] {
        targets.compactMap { draft in
            guard draft.kind == .gitRemote else { return nil }
            guard let saved = original.targets.first(where: { $0.id == draft.id }),
                  saved.kind == .gitRemote else { return nil }
            let originalURL = saved.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let newURL = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard originalURL != newURL else { return nil }
            guard let oldHost = GitRemoteHost.host(from: originalURL),
                  let newHost = GitRemoteHost.host(from: newURL),
                  oldHost != newHost else { return nil }
            return (originalURL, newURL)
        }
    }
}
