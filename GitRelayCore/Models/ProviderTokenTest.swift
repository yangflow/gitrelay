import Foundation

/// Why a provider would not accept a token.
nonisolated enum ProviderTokenRejection: String, Equatable, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case network
    case unreadableResponse
    case httpError
    case unknown

    var text: String {
        switch self {
        case .unauthorized:
            return String(localized: "Token rejected")
        case .forbidden:
            return String(localized: "Permission denied")
        case .notFound:
            return String(localized: "Account not found")
        case .network:
            return String(localized: "Could not reach the host")
        case .unreadableResponse:
            return String(localized: "Response could not be read")
        case .httpError:
            return String(localized: "The host refused the check")
        case .unknown:
            return String(localized: "Test failed")
        }
    }
}

/// What one live check came back with, before any judgement is passed on it.
///
/// Deliberately scope-shaped rather than token-shaped: the token stays in the
/// Keychain and never reaches this type.
nonisolated enum ProviderTokenProbe: Equatable, Sendable {
    case noToken
    case scopes(Set<String>)
    case refused(ProviderTokenRejection)
}

/// What 测试 found, in the three answers the row can give (plus the case where
/// there is nothing to test).
nonisolated enum ProviderTokenTestOutcome: Equatable, Sendable {
    /// The provider accepted the token. `grantedScopes` is empty when it
    /// authenticated without naming them — a GitHub fine-grained PAT sends no
    /// `X-OAuth-Scopes` header at all.
    case ok(grantedScopes: [String])
    case missingScopes([String])
    case rejected(ProviderTokenRejection)
    case noToken
}

/// Row tint for an outcome, named rather than colored so the decision can be
/// checked without SwiftUI.
nonisolated enum ProviderTokenTestTone: String, Equatable, Sendable {
    case ok
    case warning
    case error
    case neutral
}

nonisolated enum ProviderTokenTest {
    /// What this app asks each provider's token to do: list source repositories
    /// on GitHub and GitLab, create target repositories on Gitea.
    static func usage(for provider: GitProvider) -> ProviderTokenUsage {
        switch provider {
        case .github, .gitlab:
            return .sourceListing(provider: provider, organizationScope: false)
        case .gitea:
            return .giteaTargetCreate
        }
    }

    static func outcome(probe: ProviderTokenProbe, usage: ProviderTokenUsage) -> ProviderTokenTestOutcome {
        switch probe {
        case .noToken:
            return .noToken
        case .refused(let rejection):
            return .rejected(rejection)
        case .scopes(let granted):
            // Getting this far means the call authenticated. A provider that
            // will not name a token's scopes is not the same thing as a token
            // short of one, so it does not get reported as a missing scope.
            guard !granted.isEmpty else { return .ok(grantedScopes: []) }
            let validation = ProviderTokenScope.validate(grantedScopes: granted, usage: usage)
            guard validation.isFullyAuthorized else {
                return .missingScopes(validation.missingRequiredScopes)
            }
            return .ok(grantedScopes: validation.sortedGrantedScopes)
        }
    }

    static func outcome(probe: ProviderTokenProbe, provider: GitProvider) -> ProviderTokenTestOutcome {
        outcome(probe: probe, usage: usage(for: provider))
    }
}

extension ProviderTokenTestOutcome {
    var tone: ProviderTokenTestTone {
        switch self {
        case .ok:
            return .ok
        case .missingScopes:
            return .warning
        case .rejected:
            return .error
        case .noToken:
            return .neutral
        }
    }

    var symbolName: String {
        switch self {
        case .ok:
            return "checkmark.circle.fill"
        case .missingScopes:
            return "exclamationmark.triangle.fill"
        case .rejected:
            return "xmark.circle.fill"
        case .noToken:
            return "minus.circle"
        }
    }

    /// One quiet line for the account row. Never mentions the token itself.
    var rowText: String {
        switch self {
        case .ok(let grantedScopes):
            return grantedScopes.isEmpty
                ? String(localized: "Token works; scopes not reported")
                : String(localized: "Token works")
        case .missingScopes(let missing):
            return String(localized: "Missing scope: \(missing.joined(separator: ", "))")
        case .rejected(let rejection):
            return rejection.text
        case .noToken:
            return String(localized: "No token saved")
        }
    }

    /// True when the provider answered about the token, which is what 最后使用
    /// records. A token one scope short still reached its host.
    var marksAccountUsed: Bool {
        switch self {
        case .ok, .missingScopes:
            return true
        case .rejected, .noToken:
            return false
        }
    }
}
