import Foundation

/// Injectable checks so import and scheduling tests need no Keychain or filesystem.
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

nonisolated enum MirrorCredentialGate {
    static var missingCredentialsMessage: String {
        String(localized: "This mirror needs credentials before it can sync. Edit the mirror to add a token or SSH key.")
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

    static func needsCredentials(for plan: MirrorPlan, probe: CredentialProbe = .live) -> Bool {
        if isMissing(auth: plan.source.auth, probe: probe) {
            return true
        }
        for destination in plan.enabledDestinations {
            guard case .git(let endpoint) = destination.location else { continue }
            if isMissing(auth: endpoint.auth, probe: probe) {
                return true
            }
        }
        return false
    }
}
