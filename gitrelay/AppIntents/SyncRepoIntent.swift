import AppIntents
import Foundation

struct SyncRepoIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Mirror"
    static var description = IntentDescription("Start a one-way sync for a GitRelay mirror.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Mirror", requestValueDialog: "Which mirror should GitRelay sync?")
    var mirror: MirrorStatusEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Sync \(\.$mirror)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mirrorID = mirror.mirrorUUID else {
            throw AppIntentBridgeError.mirrorNotFound(mirror.mirrorName)
        }
        try AppIntentBridge.triggerSync(mirrorID: mirrorID)
        return .result(dialog: "Started sync for \(mirror.mirrorName.trimmingCharacters(in: .whitespacesAndNewlines)).")
    }
}
