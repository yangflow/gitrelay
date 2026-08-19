import WidgetKit

enum WidgetSnapshotPublisher {
    static func publish(
        repos: [RepoConfig],
        statuses: [UUID: SyncStatus],
        inProgressSyncIDs: Set<UUID>
    ) {
        let snapshot = WidgetHealthSnapshotBuilder.make(
            repos: repos,
            statuses: statuses,
            inProgressSyncIDs: inProgressSyncIDs
        )
        try? WidgetHealthSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.syncHealthWidgetKind)
    }
}
