import WidgetKit
import SwiftUI

@main
struct GitRelayWidgetBundle: WidgetBundle {
    var body: some Widget {
        SyncHealthWidget()
    }
}

struct SyncHealthWidget: Widget {
    let kind: String = WidgetConstants.syncHealthWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SyncHealthWidgetProvider()) { entry in
            SyncHealthWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sync Health")
        .description("Today's mirror sync status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SyncHealthWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetHealthSnapshot
}

struct SyncHealthWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SyncHealthWidgetEntry {
        SyncHealthWidgetEntry(
            date: .now,
            snapshot: WidgetHealthSnapshot(
                updatedAt: .now,
                summary: WidgetHealthSummaryPayload(succeededToday: 18, failedToday: 2, notRunToday: 3),
                attentionRepos: [
                    WidgetAttentionRepo(
                        id: UUID(),
                        name: "core-api",
                        status: .failure,
                        lastSyncedAt: .now,
                        message: "network failed"
                    ),
                    WidgetAttentionRepo(
                        id: UUID(),
                        name: "docs",
                        status: .diverged,
                        lastSyncedAt: .now,
                        message: "tree mismatch"
                    ),
                    WidgetAttentionRepo(
                        id: UUID(),
                        name: "legacy",
                        status: .unknown,
                        lastSyncedAt: nil,
                        message: nil
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SyncHealthWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SyncHealthWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> SyncHealthWidgetEntry {
        SyncHealthWidgetEntry(
            date: .now,
            snapshot: WidgetHealthSnapshotStore.read() ?? .empty
        )
    }
}

struct SyncHealthWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SyncHealthWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            SyncHealthMediumWidgetView(snapshot: entry.snapshot)
                .widgetURL(WidgetDeepLink.openAppURL())
        default:
            SyncHealthSmallWidgetView(snapshot: entry.snapshot)
                .widgetURL(WidgetDeepLink.openAppURL())
        }
    }
}

private struct SyncHealthSmallWidgetView: View {
    let snapshot: WidgetHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(compactCounts)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var compactCounts: String {
        "✓ \(snapshot.summary.succeededToday) / ✗ \(snapshot.summary.failedToday) / — \(snapshot.summary.notRunToday)"
    }

    private var accessibilitySummary: String {
        String(
            format: String(localized: "Today: %lld succeeded, %lld failed, %lld not run"),
            snapshot.summary.succeededToday,
            snapshot.summary.failedToday,
            snapshot.summary.notRunToday
        )
    }
}

private struct SyncHealthMediumWidgetView: View {
    let snapshot: WidgetHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(compactCounts)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }

            if snapshot.attentionRepos.isEmpty {
                Text("All mirrors look healthy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(snapshot.attentionRepos) { repo in
                        Link(destination: WidgetDeepLink.repoURL(id: repo.id)) {
                            SyncHealthAttentionRow(repo: repo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var compactCounts: String {
        "✓ \(snapshot.summary.succeededToday) / ✗ \(snapshot.summary.failedToday) / — \(snapshot.summary.notRunToday)"
    }
}

private struct SyncHealthAttentionRow: View {
    let repo: WidgetAttentionRepo

    var body: some View {
        HStack(spacing: 8) {
            WidgetStatusIcon(status: repo.status)
                .font(.caption)

            Text(repo.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            if let caption = attentionCaption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var attentionCaption: String? {
        switch repo.status {
        case .failure, .diverged:
            return repo.message
        case .syncing:
            return String(localized: "Syncing")
        case .unknown:
            return String(localized: "Not Synced")
        case .success:
            return String(localized: "Stale")
        }
    }
}

private struct WidgetStatusIcon: View {
    let status: RepoSyncStatusKind

    var body: some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .diverged:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview(as: .systemSmall) {
    SyncHealthWidget()
} timeline: {
    SyncHealthWidgetEntry(
        date: .now,
        snapshot: WidgetHealthSnapshot(
            updatedAt: .now,
            summary: WidgetHealthSummaryPayload(succeededToday: 18, failedToday: 2, notRunToday: 3),
            attentionRepos: []
        )
    )
}

#Preview(as: .systemMedium) {
    SyncHealthWidget()
} timeline: {
    SyncHealthWidgetEntry(
        date: .now,
        snapshot: WidgetHealthSnapshot(
            updatedAt: .now,
            summary: WidgetHealthSummaryPayload(succeededToday: 18, failedToday: 2, notRunToday: 3),
            attentionRepos: [
                WidgetAttentionRepo(
                    id: UUID(),
                    name: "core-api",
                    status: .failure,
                    lastSyncedAt: .now,
                    message: "network failed"
                )
            ]
        )
    )
}
#endif
