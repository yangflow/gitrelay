import Foundation

/// The most recent inbound webhook POST handled by the local listener.
nonisolated struct WebhookLastEvent: Equatable, Sendable {
    var receivedAt: Date
    var repoName: String
    var statusCode: Int
}
