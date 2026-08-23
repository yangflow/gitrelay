import Foundation

/// A Git location plus a credential reference. Secret material never belongs here.
nonisolated struct GitEndpoint: Codable, Equatable, Sendable {
    var url: String
    var auth: AuthConfig
    var provider: GitProvider?
    var accountLabel: String?

    init(
        url: String,
        auth: AuthConfig = .sshAgent,
        provider: GitProvider? = nil,
        accountLabel: String? = nil
    ) {
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.auth = auth
        self.provider = provider
        self.accountLabel = accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var identity: GitRemoteIdentity? {
        GitRemoteIdentity.any(url)
    }

    func validate(
        role: MirrorEndpointRole,
        allowMissingCredentials: Bool = false
    ) throws {
        guard !url.isEmpty else {
            throw MirrorDomainError.emptyEndpoint(role)
        }

        switch auth {
        case .sshAgent:
            break
        case .sshKey(let privateKeyPath):
            guard allowMissingCredentials
                    || !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MirrorDomainError.emptySSHKeyPath(role)
            }
        case .httpsToken(let keychainTag):
            guard !keychainTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MirrorDomainError.emptyCredentialReference(role)
            }
        }
    }
}

nonisolated enum MirrorEndpointRole: String, Codable, Equatable, Sendable {
    case source
    case destination
}
