import Foundation
import SwiftUI
import Observation

struct MirrorTargetDraft: Identifiable, Equatable {
    let id: UUID
    var url: String
    var authMode: AuthMode
    var keyPath: String
    var token: String
    var enabled: Bool
    var isExpanded: Bool
    private let preservedAuth: AuthConfig?

    init(
        id: UUID = UUID(),
        url: String = "",
        authMode: AuthMode = .sshAgent,
        keyPath: String = "",
        token: String = "",
        enabled: Bool = true,
        isExpanded: Bool = true,
        preservedAuth: AuthConfig? = nil
    ) {
        self.id = id
        self.url = url
        self.authMode = authMode
        self.keyPath = keyPath
        self.token = token
        self.enabled = enabled
        self.isExpanded = isExpanded
        self.preservedAuth = preservedAuth
    }

    init(from target: MirrorTarget, isExpanded: Bool = true) {
        self.id = target.id
        self.url = target.url
        self.enabled = target.enabled
        self.isExpanded = isExpanded
        self.preservedAuth = target.auth
        self.keyPath = ""
        self.token = ""
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
    var srcURL: String         = ""
    var targets: [MirrorTargetDraft] = [MirrorTargetDraft()]
    var srcAuthMode: AuthMode  = .sshAgent
    var srcKeyPath: String     = ""
    var srcToken: String       = ""
    var frequency: SyncFrequency = .manual
    var destructivePushPolicy: DestructivePushPolicy = .strict
    var defaultBranch: String = "main"

    var nameError: String?
    var srcError: String?
    var targetErrors: [UUID: String] = [:]

    let editingID: UUID?
    private let createdAt: Date?
    private let lastSyncedAt: Date?
    private let lastSuccessfulSyncedAt: Date?
    private let lastSyncError: String?
    private let consecutiveFailureCount: Int
    private let lastVerifiedAt: Date?
    private let divergedDetail: String?

    init(editing repo: RepoConfig? = nil) {
        editingID = repo?.id
        createdAt = repo?.createdAt
        lastSyncedAt = repo?.lastSyncedAt
        lastSuccessfulSyncedAt = repo?.lastSuccessfulSyncedAt
        lastSyncError = repo?.lastSyncError
        consecutiveFailureCount = repo?.consecutiveFailureCount ?? 0
        lastVerifiedAt = repo?.lastVerifiedAt
        divergedDetail = repo?.divergedDetail
        guard let repo else { return }
        name      = repo.name
        srcURL    = repo.srcURL
        targets   = repo.targets.map { MirrorTargetDraft(from: $0) }
        frequency = repo.frequency
        destructivePushPolicy = repo.destructivePushPolicy
        defaultBranch = repo.defaultBranch
        populate(auth: repo.srcAuth, mode: &srcAuthMode, keyPath: &srcKeyPath, token: &srcToken)
    }

    var isValid: Bool {
        nameError == nil && srcError == nil && targetErrors.isEmpty
    }

    @discardableResult
    func validate() -> Bool {
        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? "请输入名称" : nil
        srcError  = isValidGitURL(srcURL) ? nil : "请输入有效的 Git URL"

        targetErrors = [:]
        guard !targets.isEmpty else {
            return false
        }

        for target in targets {
            let trimmed = target.url.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                targetErrors[target.id] = "请输入有效的 Git URL"
            } else if !isValidGitURL(trimmed) {
                targetErrors[target.id] = "请输入有效的 Git URL"
            }
        }

        if targets.filter({ isValidGitURL($0.url) }).allSatisfy({ !$0.enabled }) {
            if targetErrors.isEmpty {
                targetErrors[targets[0].id] = "至少启用一个目标"
            }
        }

        return isValid
    }

    func addTarget() {
        targets.append(MirrorTargetDraft(isExpanded: true))
    }

    func removeTarget(id: UUID) {
        guard targets.count > 1 else { return }
        targets.removeAll { $0.id == id }
        targetErrors.removeValue(forKey: id)
    }

    func buildRepoConfig() -> RepoConfig {
        let id = editingID ?? UUID()
        let mirrorTargets = targets.map { draft in
            MirrorTarget(
                id: draft.id,
                url: draft.url.trimmingCharacters(in: .whitespaces),
                auth: buildAuth(
                    draft: draft,
                    repoID: id,
                    targetID: draft.id
                ),
                enabled: draft.enabled
            )
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
            lastVerifiedAt: lastVerifiedAt,
            divergedDetail: divergedDetail
        )
    }

    func saveTokensToKeychain(repoID: UUID) {
        if srcAuthMode == .httpsToken, !srcToken.isEmpty {
            try? KeychainService.saveToken(srcToken, tag: keychainTag(repoID: repoID, side: "src"))
        }
        for target in targets where target.authMode == .httpsToken && !target.token.isEmpty {
            try? KeychainService.saveToken(
                target.token,
                tag: keychainTag(repoID: repoID, targetID: target.id)
            )
        }
    }

    // MARK: - Private

    private func isValidGitURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("git@") { return true }
        if let u = URL(string: trimmed), u.scheme == "https" { return true }
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
}
