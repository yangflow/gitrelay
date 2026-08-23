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
                attentionMirrors: [
                    WidgetAttentionMirror(
                        id: UUID(),
                        name: "core-api",
                        status: .failure,
                        lastSyncedAt: .now,
                        message: "network failed"
                    ),
                    WidgetAttentionMirror(
                        id: UUID(),
                        name: "docs",
                        status: .diverged,
                        lastSyncedAt: .now,
                        message: "tree mismatch"
                    ),
                    WidgetAttentionMirror(
                        id: UUID(),
                        name: "design-assets",
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

/// Widget face chrome: the day label, nothing else. The counts carry the meaning.
private struct SyncHealthTodayLabel: View {
    var body: some View {
        Text(String(localized: "Today"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Succeeded / failed / not-run counts as SF Symbols plus a number, so no
/// catalog key has to start with a glyph like ✓ that cannot become a Swift
/// symbol under `STRING_CATALOG_GENERATE_SYMBOLS`.
private struct SyncHealthCountsView: View {
    let summary: WidgetHealthSummaryPayload

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            count(
                symbol: "checkmark.circle.fill",
                value: summary.succeededToday,
                color: DesignTokens.StatusColor.success
            )
            count(
                symbol: "xmark.octagon.fill",
                value: summary.failedToday,
                color: DesignTokens.StatusColor.escalatedFailure
            )
            count(
                symbol: "minus.circle",
                value: summary.notRunToday,
                color: DesignTokens.StatusColor.unknown
            )
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .minimumScaleFactor(0.75)
        .lineLimit(1)
    }

    private func count(symbol: String, value: Int, color: Color) -> some View {
        Label {
            Text(value, format: .number)
        } icon: {
            Image(systemName: symbol)
        }
        .foregroundStyle(color)
        .labelStyle(.titleAndIcon)
    }

    static func accessibilitySummary(for summary: WidgetHealthSummaryPayload) -> String {
        String(
            format: String(localized: "Today: %lld succeeded, %lld failed, %lld not run"),
            summary.succeededToday,
            summary.failedToday,
            summary.notRunToday
        )
    }
}

private struct SyncHealthSmallWidgetView: View {
    let snapshot: WidgetHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SyncHealthTodayLabel()

            Spacer(minLength: 0)

            SyncHealthCountsView(summary: snapshot.summary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(SyncHealthCountsView.accessibilitySummary(for: snapshot.summary))
        )
    }
}

private struct SyncHealthMediumWidgetView: View {
    let snapshot: WidgetHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.popoverChromeVertical) {
            HStack {
                SyncHealthTodayLabel()
                Spacer(minLength: 0)
                SyncHealthCountsView(summary: snapshot.summary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(SyncHealthCountsView.accessibilitySummary(for: snapshot.summary))
            )

            if snapshot.attentionMirrors.isEmpty {
                Text(String(localized: "All mirrors look healthy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(snapshot.attentionMirrors) { repo in
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
}

private struct SyncHealthAttentionRow: View {
    let repo: WidgetAttentionMirror

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.statusDotGap) {
            WidgetStatusDotView(status: repo.status)

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
        case .queued:
            return String(localized: "Queued")
        case .unknown:
            return String(localized: "Not Synced")
        case .success:
            return String(localized: "Stale")
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
            attentionMirrors: []
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
            attentionMirrors: [
                WidgetAttentionMirror(
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
