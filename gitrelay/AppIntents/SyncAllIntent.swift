import AppIntents
import Foundation

struct SyncAllIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync All Repositories"
    static var description = IntentDescription("Start a one-way mirror sync for every GitRelay repository.")
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Sync all repositories")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentBridge.triggerSyncAll()
        return .result(dialog: "Started sync for all repositories.")
    }
}
