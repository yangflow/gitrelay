import Foundation
import Observation

@MainActor
@Observable
final class WebhookController {
    let preferences: WebhookPreferencesStore
    private let library: MirrorLibraryModel
    private let operations: MirrorOperationsController
    private let issues: AppIssueModel
    private let listener: WebhookListener

    var secretProvider: (UUID) -> String? = { WebhookSecretStore.loadSecret(repoID: $0) }
    private(set) var lastEvent: WebhookLastEvent?

    var listenPort: UInt16? { listener.port }
    var isListenerRunning: Bool { listener.isRunning }
    var testTargetMirror: MirrorSnapshot? { library.mirrors.first(where: \.webhookEnabled) }

    var canSendTest: Bool {
        guard preferences.preferences.listenerEnabled,
              listenPort != nil,
              let mirror = testTargetMirror,
              let secret = secretProvider(mirror.id),
              !secret.isEmpty else { return false }
        return true
    }

    init(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        preferences: WebhookPreferencesStore,
        issues: AppIssueModel,
        listener: WebhookListener? = nil
    ) {
        let listener = listener ?? WebhookListener()
        self.library = library
        self.operations = operations
        self.preferences = preferences
        self.issues = issues
        self.listener = listener
        listener.onRequest = { [weak self] request in
            await MainActor.run { [weak self] in
                self?.handle(request)
                    ?? WebhookHTTPResponse.plain(503, "Service Unavailable", message: "unavailable\n")
            }
        }
        refreshListener()
    }

    func handle(_ request: WebhookHTTPRequest) -> WebhookHTTPResponse {
        let result = MirrorWebhookRouter.decide(
            request: request,
            plans: library.plans,
            secretForMirror: { [secretProvider] in secretProvider($0) }
        )
        recordLastEvent(request: request, response: result.httpResponse)
        if let mirrorID = result.syncRepoID {
            operations.triggerSync(mirrorID: mirrorID)
        }
        return result.httpResponse
    }

    func hookPath(for mirror: MirrorSnapshot) -> String {
        WebhookURLTemplate.hookPath(pathID: mirror.webhookPathID)
    }

    func displayURL(for mirror: MirrorSnapshot) -> String {
        WebhookURLTemplate.displayURL(
            preferences: preferences.preferences,
            port: listenPort,
            pathID: mirror.webhookPathID
        )
    }

    func sendTest() async {
        guard let port = listenPort,
              let mirror = testTargetMirror,
              let secret = secretProvider(mirror.id),
              let request = WebhookLocalTestClient.makePingRequest(
                  port: port,
                  pathID: mirror.webhookPathID,
                  secret: secret
              ) else { return }
        do {
            _ = try await WebhookLocalTestClient.send(request: request)
        } catch {
            lastEvent = WebhookLastEvent(
                receivedAt: Date(),
                repoName: mirror.name,
                statusCode: 0
            )
        }
    }

    func refreshListener() {
        guard preferences.preferences.listenerEnabled else {
            listener.stop()
            return
        }
        guard !listener.isRunning else { return }
        do {
            try listener.start()
        } catch {
            issues.report(
                String(
                    format: String.loc("Failed to start the webhook listener: %@"),
                    error.localizedDescription
                )
            )
            listener.stop()
        }
    }

    func removeSecret(mirrorID: UUID) {
        WebhookSecretStore.deleteSecret(repoID: mirrorID)
    }

    private func recordLastEvent(
        request: WebhookHTTPRequest,
        response: WebhookHTTPResponse
    ) {
        guard request.method.uppercased() == "POST" else { return }
        guard case .hook(let pathID) = WebhookRoute.parse(
            method: request.method,
            path: request.path
        ) else { return }

        let normalizedID = pathID.lowercased()
        let name = library.plans.first(where: {
            WebhookPushMapper.pathID(for: $0.id).lowercased() == normalizedID
        })?.name ?? String.loc("Unknown repository")
        lastEvent = WebhookLastEvent(
            receivedAt: Date(),
            repoName: name,
            statusCode: response.statusCode
        )
    }
}
