import Foundation

/// Injectable checks so export/import and scheduling tests need no Keychain or filesystem.
nonisolated struct CredentialProbe: Sendable {
    var hasHTTPSToken: @Sendable (String) -> Bool
    var isSSHKeyReadable: @Sendable (String) -> Bool

    static let live = CredentialProbe(
        hasHTTPSToken: { tag in
            guard let token = try? KeychainService.loadToken(tag: tag) else { return false }
            return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        },
        isSSHKeyReadable: { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let expanded = (trimmed as NSString).expandingTildeInPath
            return FileManager.default.isReadableFile(atPath: expanded)
        }
    )

    /// Treats every HTTPS/SSH credential as missing — useful for import unit tests.
    static let alwaysMissing = CredentialProbe(
        hasHTTPSToken: { _ in false },
        isSSHKeyReadable: { _ in false }
    )

    /// Treats every credential as present.
    static let alwaysPresent = CredentialProbe(
        hasHTTPSToken: { _ in true },
        isSSHKeyReadable: { _ in true }
    )
}

nonisolated enum RepoCredentialGate {
    static var missingCredentialsMessage: String {
        String.loc("This repository needs credentials before it can sync. Edit the repository to add a token or SSH key.")
    }

    static func isMissing(auth: AuthConfig, probe: CredentialProbe = .live) -> Bool {
        switch auth {
        case .sshAgent:
            return false
        case .sshKey(let path):
            return !probe.isSSHKeyReadable(path)
        case .httpsToken(let tag):
            return !probe.hasHTTPSToken(tag)
        }
    }

    static func needsCredentials(for repo: RepoConfig, probe: CredentialProbe = .live) -> Bool {
        if isMissing(auth: repo.srcAuth, probe: probe) {
            return true
        }
        for target in repo.targets where target.enabled && target.kind == .gitRemote {
            if isMissing(auth: target.auth, probe: probe) {
                return true
            }
        }
        return false
    }

    /// Recomputes the persisted flag from live credential availability.
    static func refreshedNeedsCredentials(for repo: RepoConfig, probe: CredentialProbe = .live) -> Bool {
        needsCredentials(for: repo, probe: probe)
    }
}
