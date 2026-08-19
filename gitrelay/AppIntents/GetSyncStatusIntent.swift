import AppIntents
import Foundation

struct GetSyncStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Sync Status"
    static var description = IntentDescription("Return the latest sync status for a named GitRelay repository.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Repository Name", requestValueDialog: "Which repository status should GitRelay return?")
    var repoName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get sync status for \(\.$repoName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RepoSyncStatusEntity> & ProvidesDialog {
        let snapshot = try AppIntentBridge.syncStatusSnapshot(repoName: repoName)
        let entity = RepoSyncStatusEntity(snapshot: snapshot)
        let timestamp = snapshot.lastSyncedAt.map(Self.timestampFormatter.string) ?? "never"
        let dialog = "\(snapshot.repoName): \(snapshot.status.rawValue) (last synced \(timestamp))."
        return .result(value: entity, dialog: IntentDialog(stringLiteral: dialog))
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
