import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class AddEditRepoViewModel {
    var name: String           = ""
    var srcURL: String         = ""
    var dstURL: String         = ""
    var srcAuthMode: AuthMode  = .sshAgent
    var srcKeyPath: String     = ""
    var srcToken: String       = ""
    var dstAuthMode: AuthMode  = .sshAgent
    var dstKeyPath: String     = ""
    var dstToken: String       = ""
    var frequency: SyncFrequency = .manual

    var nameError: String?
    var srcError: String?
    var dstError: String?

    let editingID: UUID?

    init(editing repo: RepoConfig? = nil) {
        editingID = repo?.id
        guard let repo else { return }
        name      = repo.name
        srcURL    = repo.srcURL
        dstURL    = repo.dstURL
        frequency = repo.frequency
        populate(auth: repo.srcAuth, mode: &srcAuthMode, keyPath: &srcKeyPath, token: &srcToken)
        populate(auth: repo.dstAuth, mode: &dstAuthMode, keyPath: &dstKeyPath, token: &dstToken)
    }

    var isValid: Bool {
        nameError == nil && srcError == nil && dstError == nil
    }

    @discardableResult
    func validate() -> Bool {
        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? "请输入名称" : nil
        srcError  = isValidGitURL(srcURL) ? nil : "请输入有效的 Git URL"
        dstError  = isValidGitURL(dstURL) ? nil : "请输入有效的 Git URL"
        return isValid
    }

    func buildRepoConfig() -> RepoConfig {
        let id = editingID ?? UUID()
        return RepoConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            srcURL: srcURL.trimmingCharacters(in: .whitespaces),
            dstURL: dstURL.trimmingCharacters(in: .whitespaces),
            srcAuth: buildAuth(mode: srcAuthMode, keyPath: srcKeyPath, token: srcToken, repoID: id, side: "src"),
            dstAuth: buildAuth(mode: dstAuthMode, keyPath: dstKeyPath, token: dstToken, repoID: id, side: "dst"),
            frequency: frequency
        )
    }

    func saveTokensToKeychain(repoID: UUID) {
        if srcAuthMode == .httpsToken, !srcToken.isEmpty {
            try? KeychainService.saveToken(srcToken, tag: keychainTag(repoID: repoID, side: "src"))
        }
        if dstAuthMode == .httpsToken, !dstToken.isEmpty {
            try? KeychainService.saveToken(dstToken, tag: keychainTag(repoID: repoID, side: "dst"))
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
}
