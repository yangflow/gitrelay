import AppIntents

struct GitRelayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncAllIntent(),
            phrases: [
                "Sync all repos in \(.applicationName)",
                "Sync everything with \(.applicationName)",
                "Run sync all in \(.applicationName)",
            ],
            shortTitle: "Sync All",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: SyncRepoIntent(),
            phrases: [
                "Sync \(\.$repo) with \(.applicationName)",
                "Sync repo \(\.$repo) in \(.applicationName)",
                "Run sync for \(\.$repo) in \(.applicationName)",
            ],
            shortTitle: "Sync Repository",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: GetSyncStatusIntent(),
            phrases: [
                "Get sync status for \(\.$repo) in \(.applicationName)",
                "Check \(\.$repo) sync status in \(.applicationName)",
                "What is the sync status of \(\.$repo) in \(.applicationName)",
            ],
            shortTitle: "Get Sync Status",
            systemImageName: "checkmark.circle"
        )
    }
}
