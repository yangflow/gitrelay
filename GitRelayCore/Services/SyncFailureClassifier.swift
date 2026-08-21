import Foundation

/// Recognized sync failure categories already produced by `SyncEngine.classifyError`.
/// Presentation code should map these to next-step actions; do not re-parse raw git stderr.
enum SyncFailureKind: Equatable, Sendable {
    case authentication
    case repositoryNotFound
    case network
    case pushRejected
    case other
}

/// Pure classification shared by SyncEngine (message text) and failure next-step UI.
/// Semantics match the historical `SyncEngine.classifyError` patterns — do not broaden matchers here.
enum SyncFailureClassifier {
    /// Canonical display strings historically returned by SyncEngine for known kinds.
    static func displayMessage(for kind: SyncFailureKind) -> String? {
        switch kind {
        case .authentication:
            return "Authentication failed — check credentials"
        case .repositoryNotFound:
            return "Repository not found — check URL"
        case .network:
            return "Network error — check connectivity"
        case .pushRejected:
            return "Push rejected — destination has diverged"
        case .other:
            return nil
        }
    }

    /// Classifies an error the same way SyncEngine has historically done, returning the display message.
    static func classifyError(_ error: Error) -> String {
        if let syncError = error as? SyncEngineError {
            return syncError.localizedDescription
        }
        if let destructivePushError = error as? DestructivePushError {
            return destructivePushError.localizedDescription
        }
        if let archiveError = error as? ArchiveError {
            return archiveError.localizedDescription ?? "Archive failed"
        }

        let raw = SyncEngine.redactCredentials(error.localizedDescription)
        let kind = kind(fromRedactedMessage: raw)
        if let display = displayMessage(for: kind) {
            return display
        }
        return raw
    }

    /// Maps a redacted (or already-classified) message to a kind.
    static func kind(fromStoredMessage message: String) -> SyncFailureKind {
        let redacted = SyncEngine.redactCredentials(message)
        let lower = redacted.lowercased()

        if let known = knownKind(matching: lower) {
            return known
        }
        return kind(fromRedactedMessage: redacted)
    }

    // MARK: - Private

    private static func knownKind(matching lower: String) -> SyncFailureKind? {
        if let auth = displayMessage(for: .authentication)?.lowercased(), lower.contains(auth) {
            return .authentication
        }
        if let missing = displayMessage(for: .repositoryNotFound)?.lowercased(), lower.contains(missing) {
            return .repositoryNotFound
        }
        if let network = displayMessage(for: .network)?.lowercased(), lower.contains(network) {
            return .network
        }
        if let rejected = displayMessage(for: .pushRejected)?.lowercased(), lower.contains(rejected) {
            return .pushRejected
        }
        return nil
    }

    /// Pattern matchers mirrored from the historical SyncEngine.classifyError body.
    private static func kind(fromRedactedMessage raw: String) -> SyncFailureKind {
        let lower = raw.lowercased()
        if lower.contains("authentication failed") || lower.contains("permission denied") ||
           lower.contains("could not read username") || lower.contains("invalid username or password") ||
           lower.contains("access denied") {
            return .authentication
        }
        if lower.contains("repository not found") || (lower.contains("not found") && lower.contains("git")) {
            return .repositoryNotFound
        }
        if lower.contains("could not resolve host") || lower.contains("connection timed out") ||
           lower.contains("network is unreachable") || lower.contains("ssl certificate") {
            return .network
        }
        if lower.contains("rejected") || lower.contains("non-fast-forward") {
            return .pushRejected
        }
        return .other
    }
}
