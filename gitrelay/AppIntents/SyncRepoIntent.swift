import AppIntents
import Foundation

struct SyncRepoIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Repository"
    static var description = IntentDescription("Start a one-way mirror sync for a named GitRelay repository.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Repository Name", requestValueDialog: "Which repository should GitRelay sync?")
    var repoName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Sync \(\.$repoName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentBridge.triggerSync(repoName: repoName)
        return .result(dialog: "Started sync for \(repoName.trimmingCharacters(in: .whitespacesAndNewlines)).")
    }
}
