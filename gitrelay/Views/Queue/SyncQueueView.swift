import SwiftUI

/// 队列: repositories holding or waiting for a sync slot.
///
/// Reads the statuses and phases `AppViewModel` already publishes — nothing
/// here schedules or admits work.
struct SyncQueueView: View {
    @Environment(AppViewModel.self) private var appVM
    let onOpen: (UUID) -> Void

    private var entries: [SyncQueueEntry] { appVM.syncQueueEntries }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeaderView(title: MainSidebarItem.queue.title)

            if entries.isEmpty {
                PaneEmptyStateView(
                    systemImage: "checklist",
                    message: String(localized: "Nothing is syncing or queued.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(entries) { entry in
                            SyncQueueRowView(entry: entry) {
                                appVM.cancelSync(repoID: entry.id)
                            }
                            .onTapGesture { onOpen(entry.id) }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
                    .padding(.bottom, DesignTokens.Spacing.paneHeaderHorizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SyncQueueRowView: View {
    let entry: SyncQueueEntry
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: entry.provider?.symbolName ?? "folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(entry.name)
                .lineLimit(1)

            Spacer(minLength: DesignTokens.Spacing.sm)

            Text(entry.state.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if entry.state.isSyncing {
                // No total is known mid-transfer, so the bar stays indeterminate.
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: DesignTokens.Layout.queueProgressWidth)
            }

            Button(role: .cancel, action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Cancel Sync"))
            .accessibilityLabel(String(localized: "Cancel Sync"))
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitRelayPanelSurface(cornerRadius: DesignTokens.CornerRadius.panel)
        .contentShape(Rectangle())
    }
}
