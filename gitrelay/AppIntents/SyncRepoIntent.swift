import AppIntents
import Foundation

struct SyncRepoIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Repository"
    static var description = IntentDescription("Start a one-way mirror sync for a named GitRelay repository.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Repository", requestValueDialog: "Which repository should GitRelay sync?")
    var repo: RepoSyncStatusEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Sync \(\.$repo)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentBridge.triggerSync(repoName: repo.repoName)
        return .result(dialog: "Started sync for \(repo.repoName.trimmingCharacters(in: .whitespacesAndNewlines)).")
    }
}
