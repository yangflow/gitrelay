import SwiftUI

struct MenuBarRepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    var recentRecords: [SyncRecord] = []
    let onOpen: () -> Void
    let onSync: () -> Void
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void

    @State private var isHovered = false

    private var presentation: RepoRowHealthPresentation.Caption {
        RepoRowHealthPresentation.caption(for: repo, status: status)
    }

    private var nextStep: RepoFailureNextStep {
        RepoFailureNextStep.make(repo: repo, status: status, recentRecords: recentRecords)
    }

    private var canSync: Bool {
        MenuBarPopoverFilter.canTriggerSync(for: status)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.statusDotGap) {
            StatusDotView(status: status)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(repo.name)
                    .foregroundStyle(
                        isEscalatedFailure
                            ? DesignTokens.StatusColor.escalatedFailure
                            : .primary
                    )
                    .lineLimit(1)
                RepoRowCaptionView(caption: presentation)
                RepoFailureNextStepActionsView(
                    nextStep: nextStep,
                    compact: true,
                    onReenterCredentials: onReenterCredentials,
                    onOpenLog: onOpenLog
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isEscalatedFailure, let count = RepoRowHealthPresentation.failureBadgeCount(for: repo) {
                FailureCountBadge(count: count)
            }
            if isHovered {
                Button(action: onSync) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Sync Now")
                .disabled(!canSync)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            isHovered
                ? DesignTokens.Surface.selectionTint
                : Color.clear
        )
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
    }

    private var isEscalatedFailure: Bool {
        RepoRowHealthPresentation.showsFailureBadge(for: repo)
    }
}
