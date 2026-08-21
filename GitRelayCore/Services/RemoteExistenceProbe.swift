import Foundation

/// Credentials for a preflight probe. The add sheet has them in hand as draft
/// values before anything is written to the Keychain, so they travel as plain
/// fields here and are never logged.
nonisolated struct RemoteProbeCredentials: Equatable, Sendable {
    let mode: AuthMode
    let sshKeyPath: String
    let token: String

    init(mode: AuthMode = .sshAgent, sshKeyPath: String = "", token: String = "") {
        self.mode = mode
        self.sshKeyPath = sshKeyPath
        self.token = token
    }
}

/// Turns a failed `ls-remote` into one of the preflight answers.
///
/// These patterns are intentionally wider than ``SyncFailureClassifier`` — a
/// probe has to separate "no such repository" from "credentials refused" across
/// GitHub, GitLab, and Gitea wording, where a sync only needs one failure line.
nonisolated enum AddPreflightProbeClassifier {
    /// Credentials are checked first: several hosts answer "not found" for a
    /// private repository, but only a refused credential says so out loud.
    private static let authenticationPatterns = [
        "authentication failed",
        "permission denied",
        "could not read username",
        "could not read password",
        "invalid username or password",
        "access denied",
        "terminal prompts disabled",
        "authentication required",
        "unauthorized",
        "403 forbidden",
        "publickey"
    ]

    private static let missingPatterns = [
        "repository not found",
        "not found",
        "does not exist",
        "could not be found",
        "project you were looking for",
        "does not appear to be a git repository",
        "no such file or directory",
        "404"
    ]

    private static let unreachablePatterns = [
        "could not resolve host",
        "connection timed out",
        "connection refused",
        "network is unreachable",
        "no route to host",
        "operation timed out",
        "temporary failure in name resolution",
        "ssl certificate"
    ]

    static func result(forFailureMessage message: String) -> AddPreflightProbeResult {
        let lower = message.lowercased()
        if authenticationPatterns.contains(where: lower.contains) {
            return .authenticationFailed
        }
        if missingPatterns.contains(where: lower.contains) {
            return .missing
        }
        if unreachablePatterns.contains(where: lower.contains) {
            return .unreachable
        }
        return .unreachable
    }
}

protocol RemoteExistenceProbing: Sendable {
    nonisolated func probe(url: String, credentials: RemoteProbeCredentials) async -> AddPreflightProbeResult
}

/// Asks the remote itself with `git ls-remote`, which needs no API token and
/// works for every host GitRelay mirrors. An existing but empty repository
/// answers with no refs and exit 0, so it counts as reachable.
nonisolated struct GitRemoteExistenceProbe: RemoteExistenceProbing {
    let timeout: Duration

    init(timeout: Duration = .seconds(12)) {
        self.timeout = timeout
    }

    func probe(url: String, credentials: RemoteProbeCredentials) async -> AddPreflightProbeResult {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skipped }

        let runner = GitRunner()
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            await runner.cancel()
        }
        defer { watchdog.cancel() }

        do {
            _ = try await runner.run(
                args: ["ls-remote", "--heads", Self.probeURL(url: trimmed, credentials: credentials)],
                env: Self.environment(url: trimmed, credentials: credentials)
            )
            return .reachable
        } catch GitError.cancelled {
            return .unreachable
        } catch GitError.gitNotFound {
            return .skipped
        } catch GitError.processError(_, let stderr) {
            return AddPreflightProbeClassifier.result(
                forFailureMessage: SyncEngine.redactCredentials(stderr)
            )
        } catch {
            return .unreachable
        }
    }

    /// HTTPS token remotes carry the token as userinfo, the same shape the sync
    /// engine uses. SSH remotes are left untouched.
    static func probeURL(url: String, credentials: RemoteProbeCredentials) -> String {
        guard credentials.mode == .httpsToken else { return url }
        let token = credentials.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              var components = URLComponents(string: url),
              components.scheme?.lowercased() == "https" || components.scheme?.lowercased() == "http"
        else { return url }
        components.user = token
        return components.string ?? url
    }

    /// A probe must fail instead of asking: no terminal prompt, no askpass
    /// window, and `BatchMode` so a passphrase-locked key gives up immediately.
    static func environment(url: String, credentials: RemoteProbeCredentials) -> [String: String] {
        var env = [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "echo",
            "SSH_ASKPASS_REQUIRE": "never"
        ]
        switch credentials.mode {
        case .sshAgent:
            env["GIT_SSH_COMMAND"] = "ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
        case .sshKey:
            let path = credentials.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            env["GIT_SSH_COMMAND"] = path.isEmpty
                ? "ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
                : "ssh -i \(path) -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
        case .httpsToken:
            break
        }
        return env
    }
}
