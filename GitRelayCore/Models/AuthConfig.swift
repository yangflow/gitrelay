import Foundation

nonisolated enum AuthConfig: Codable, Equatable, Sendable {
    case sshAgent
    case sshKey(privateKeyPath: String)
    case httpsToken(keychainTag: String)

    var displayName: String {
        switch self {
        case .sshAgent:   return "SSH Agent"
        case .sshKey:     return "SSH Key"
        case .httpsToken: return "HTTPS Token"
        }
    }
}

/// Builds the shell command consumed by Git through `GIT_SSH_COMMAND`.
///
/// Git asks a shell to split this value, so a user-controlled key path must be
/// quoted as one shell argument. Keeping the quoting in one place also prevents
/// probes, verification, and synchronization from drifting apart.
nonisolated enum GitSSHCommand {
    static let agent = "ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

    static func usingPrivateKey(at path: String) -> String {
        "ssh -i \(shellQuoted(path)) -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

/// Low-level sanitization shared by domain, persistence, and execution layers.
/// It intentionally has no dependency on the Git runner.
nonisolated enum CredentialRedactor {
    static func redact(_ message: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "https://[^@]+@") else {
            return message
        }
        return regex.stringByReplacingMatches(
            in: message,
            range: NSRange(message.startIndex..., in: message),
            withTemplate: "https://****@"
        )
    }
}
