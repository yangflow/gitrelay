import AppIntents
import Foundation

struct GetSyncStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Mirror Status"
    static var description = IntentDescription("Return the latest health and sync status for a GitRelay mirror.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Mirror", requestValueDialog: "Which mirror status should GitRelay return?")
    var mirror: MirrorStatusEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get mirror status for \(\.$mirror)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MirrorStatusEntity> & ProvidesDialog {
        guard let mirrorID = mirror.mirrorUUID else {
            throw AppIntentBridgeError.mirrorNotFound(mirror.mirrorName)
        }
        let snapshot = try AppIntentBridge.mirrorStatusSnapshot(mirrorID: mirrorID)
        let entity = MirrorStatusEntity(snapshot: snapshot)
        let timestamp = snapshot.lastSuccessfulAt.map(Self.timestampFormatter.string) ?? "never"
        let dialog = "\(snapshot.mirrorName): \(snapshot.status.rawValue) (last synced \(timestamp))."
        return .result(value: entity, dialog: IntentDialog(stringLiteral: dialog))
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
