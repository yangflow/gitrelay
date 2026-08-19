import Foundation

struct WidgetHealthSummaryPayload: Codable, Equatable, Sendable {
    var succeededToday: Int
    var failedToday: Int
    var notRunToday: Int

    init(
        succeededToday: Int,
        failedToday: Int,
        notRunToday: Int
    ) {
        self.succeededToday = succeededToday
        self.failedToday = failedToday
        self.notRunToday = notRunToday
    }

    init(summary: SyncHealthSummary) {
        self.init(
            succeededToday: summary.succeededToday,
            failedToday: summary.failedToday,
            notRunToday: summary.notRunToday
        )
    }
}

struct WidgetAttentionRepo: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var status: RepoSyncStatusKind
    var lastSyncedAt: Date?
    var message: String?
}

struct WidgetHealthSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var summary: WidgetHealthSummaryPayload
    var attentionRepos: [WidgetAttentionRepo]

    static let empty = WidgetHealthSnapshot(
        updatedAt: .distantPast,
        summary: WidgetHealthSummaryPayload(succeededToday: 0, failedToday: 0, notRunToday: 0),
        attentionRepos: []
    )
}
