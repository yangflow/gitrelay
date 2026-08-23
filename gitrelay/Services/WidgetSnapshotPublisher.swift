import WidgetKit

enum WidgetSnapshotPublisher {
    static func publish() {
        let plans = (try? MirrorPlanStore().load()) ?? []
        let health = (try? MirrorStateStore().load()) ?? [:]
        let snapshot = WidgetHealthSnapshotBuilder.make(
            plans: plans,
            health: health
        )
        try? WidgetHealthSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.syncHealthWidgetKind)
    }
}
