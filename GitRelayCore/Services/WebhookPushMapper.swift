import Foundation

/// Outcome of validating an inbound webhook HTTP request.
nonisolated enum WebhookHandlingResult: Equatable, Sendable {
    case healthOK
    case pingAcknowledged
    case acceptedSync(repoID: UUID)
    case ignored(reason: String)
    case unauthorized
    case notFound
    case methodNotAllowed

    var shouldTriggerSync: Bool {
        if case .acceptedSync = self { return true }
        return false
    }

    var syncRepoID: UUID? {
        if case .acceptedSync(let id) = self { return id }
        return nil
    }

    var httpResponse: WebhookHTTPResponse {
        switch self {
        case .healthOK:
            return .plain(200, "OK", message: "ok\n")
        case .pingAcknowledged:
            return .plain(200, "OK", message: "pong\n")
        case .acceptedSync:
            return .plain(202, "Accepted", message: "sync queued\n")
        case .ignored(let reason):
            return .plain(200, "OK", message: "ignored: \(reason)\n")
        case .unauthorized:
            return .plain(401, "Unauthorized", message: "invalid signature\n")
        case .notFound:
            return .plain(404, "Not Found", message: "not found\n")
        case .methodNotAllowed:
            return .plain(405, "Method Not Allowed", message: "POST required\n")
        }
    }
}

/// Maps HTTP hook deliveries to per-repo sync decisions (independent of frequency scheduling).
nonisolated enum WebhookPushMapper {
    struct HookTarget: Equatable, Sendable {
        let repoID: UUID
        /// Path segment for `POST /hook/<pathID>`.
        let pathID: String
        let enabled: Bool
    }

    static func pathID(for repoID: UUID) -> String {
        repoID.uuidString.lowercased()
    }

    static func decide(
        request: WebhookHTTPRequest,
        targets: [HookTarget],
        secretForRepo: (UUID) -> String?
    ) -> WebhookHandlingResult {
        switch WebhookRoute.parse(method: request.method, path: request.path) {
        case .health:
            let method = request.method.uppercased()
            return (method == "GET" || method == "HEAD") ? .healthOK : .methodNotAllowed
        case .notFound:
            return .notFound
        case .hook(let pathID):
            return handleHook(
                pathID: pathID,
                request: request,
                targets: targets,
                secretForRepo: secretForRepo
            )
        }
    }

    private static func handleHook(
        pathID: String,
        request: WebhookHTTPRequest,
        targets: [HookTarget],
        secretForRepo: (UUID) -> String?
    ) -> WebhookHandlingResult {
        guard request.method.uppercased() == "POST" else {
            return .methodNotAllowed
        }

        let normalizedID = pathID.lowercased()
        guard let target = targets.first(where: { $0.pathID.lowercased() == normalizedID }) else {
            return .notFound
        }
        guard target.enabled else {
            return .ignored(reason: "webhook disabled for repo")
        }
        guard let secret = secretForRepo(target.repoID), !secret.isEmpty else {
            return .unauthorized
        }

        let githubSig = request.header("X-Hub-Signature-256")
        let gitlabToken = request.header("X-Gitlab-Token")
        guard WebhookHMACVerifier.verify(
            payload: request.body,
            secret: secret,
            githubSignatureHeader: githubSig,
            gitlabTokenHeader: gitlabToken
        ) else {
            return .unauthorized
        }

        let githubEvent = request.header("X-GitHub-Event")?.lowercased()
        let gitlabEvent = request.header("X-Gitlab-Event")?.lowercased()
        let giteaEvent = request.header("X-Gitea-Event")?.lowercased()

        if githubEvent == "ping" || giteaEvent == "ping" {
            return .pingAcknowledged
        }

        let isPush =
            githubEvent == "push"
            || giteaEvent == "push"
            || gitlabEvent == "push hook"
            || (githubEvent == nil && gitlabEvent == nil && giteaEvent == nil
                && looksLikePushPayload(request.body))

        guard isPush else {
            let label = githubEvent ?? gitlabEvent ?? giteaEvent ?? "unknown"
            return .ignored(reason: "event \(label)")
        }

        return .acceptedSync(repoID: target.repoID)
    }

    /// Fallback when providers omit event headers (e.g. local curl tests with a push-shaped body).
    private static func looksLikePushPayload(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        if object["ref"] is String { return true }
        if object["commits"] is [Any] { return true }
        return false
    }
}
