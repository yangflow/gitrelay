import AppIntents
import Foundation

struct SyncAllIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync All Mirrors"
    static var description = IntentDescription("Start a one-way sync for every GitRelay mirror.")
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Sync all mirrors")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentBridge.triggerSyncAll()
        return .result(dialog: "Started sync for all mirrors.")
    }
}
