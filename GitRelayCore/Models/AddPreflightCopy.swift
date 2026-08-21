import Foundation

/// The quiet copy for the add sheet's preflight line and its buttons. One line,
/// no banners: every state below writes into the same caption slot under the
/// two fields.
nonisolated enum AddPreflightCopy {
    /// Short name of the host that would receive the new repository, so the
    /// caption never promises "GitLab" for a GitHub URL.
    static func destinationProviderLabel(destinationURL: String) -> String? {
        guard let host = GitRemoteHost.host(from: destinationURL), !host.isEmpty else { return nil }
        switch GitRemoteHost.inferredProvider(from: host) {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .gitea:  return host
        }
    }

    static func caption(for decision: AddPreflightDecision, destinationURL: String) -> String? {
        switch decision {
        case .idle, .ready:
            return nil
        case .duplicatePair:
            return String(localized: "This mirror already exists. Open it or change the target.")
        case .destinationMissing:
            guard let provider = destinationProviderLabel(destinationURL: destinationURL) else {
                return String(localized: "The destination repository does not exist. An empty one will be created before the first sync.")
            }
            return String(localized: "The destination repository does not exist. An empty one will be created on \(provider).")
        case .sourceMissing:
            return String(localized: "The source repository was not found. Check the URL.")
        case .authenticationFailed(.source):
            return String(localized: "The source refused the credentials. Take a look at its token or account.")
        case .authenticationFailed(.destination):
            return String(localized: "The destination refused the credentials. Take a look at its token or account.")
        case .unreachable(.source):
            return String(localized: "Could not reach the source just now.")
        case .unreachable(.destination):
            return String(localized: "Could not reach the destination just now.")
        }
    }

    static var checkingCaption: String {
        String(localized: "Checking both URLs…")
    }

    static var creatingDestinationCaption: String {
        String(localized: "Creating the destination repository…")
    }

    /// Shown when the destination host has no saved token to create with.
    static func missingCreateTokenCaption(destinationURL: String) -> String {
        guard let provider = destinationProviderLabel(destinationURL: destinationURL) else {
            return String(localized: "Creating the destination needs an API token. Add one in the accounts pane, or change the target.")
        }
        return String(localized: "Creating the destination needs a \(provider) token. Add one in the accounts pane, or change the target.")
    }

    static func createFailedCaption(_ message: String) -> String {
        String(localized: "Could not create the destination repository: \(message)")
    }

    static var createAndStartSyncTitle: String {
        String(localized: "Create and Start Sync")
    }

    static var openExistingTitle: String {
        String(localized: "Open the Existing One")
    }

    static var addAnywayTitle: String {
        String(localized: "Add Anyway")
    }
}
