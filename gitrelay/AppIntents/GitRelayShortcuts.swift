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
                "Sync \(\.$repoName) with \(.applicationName)",
                "Sync repo \(\.$repoName) in \(.applicationName)",
                "Run sync for \(\.$repoName) in \(.applicationName)",
            ],
            shortTitle: "Sync Repository",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: GetSyncStatusIntent(),
            phrases: [
                "Get sync status for \(\.$repoName) in \(.applicationName)",
                "Check \(\.$repoName) sync status in \(.applicationName)",
                "What is the sync status of \(\.$repoName) in \(.applicationName)",
            ],
            shortTitle: "Get Sync Status",
            systemImageName: "checkmark.circle"
        )
    }
}
