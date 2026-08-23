import AppIntents

struct GitRelayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncAllIntent(),
            phrases: [
                "Sync all mirrors in \(.applicationName)",
                "Sync everything with \(.applicationName)",
                "Run sync all in \(.applicationName)",
            ],
            shortTitle: "Sync All",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: SyncRepoIntent(),
            phrases: [
                "Sync \(\.$mirror) with \(.applicationName)",
                "Sync mirror \(\.$mirror) in \(.applicationName)",
                "Run sync for \(\.$mirror) in \(.applicationName)",
            ],
            shortTitle: "Sync Mirror",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: GetSyncStatusIntent(),
            phrases: [
                "Get sync status for \(\.$mirror) in \(.applicationName)",
                "Check \(\.$mirror) sync status in \(.applicationName)",
                "What is the sync status of \(\.$mirror) in \(.applicationName)",
            ],
            shortTitle: "Get Mirror Status",
            systemImageName: "checkmark.circle"
        )
    }
}
