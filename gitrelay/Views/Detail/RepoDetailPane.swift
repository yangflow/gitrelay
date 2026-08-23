import SwiftUI

/// Operational repository detail: health and primary actions stay visible while
/// technical information scrolls beneath them.
struct RepoDetailPane: View {
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorManagementController.self) private var management
    @Environment(MirrorCacheController.self) private var cache
    @Environment(SecurityController.self) private var security
    @Environment(WorkspaceModel.self) private var workspace

    let repo: MirrorSnapshot
    let onBack: () -> Void
    let onEdit: () -> Void

    @State private var pendingConfirmation: RepositoryConfirmation?

    private var status: SyncStatus {
        operations.statuses[repo.id] ?? .unknown
    }

    private var row: MirrorSummary {
        MirrorSummaryProjection.row(for: repo, status: status)
    }

    private var scheduleState: RepoScheduleState {
        RepoScheduleState.make(repo: repo)
    }

    private var isSyncBusy: Bool {
        status == .syncing || status == .queued
    }

    private var isVerifying: Bool {
        operations.inProgressVerifyIDs.contains(repo.id)
    }

    private var hasLocalCache: Bool {
        cache.mirrorUsages.contains {
            $0.repoID == repo.id && $0.sizeBytes > 0
        }
    }

    private var presentation: MirrorDetailPresentation {
        MirrorDetailPresentation.make(
            mirror: repo,
            activity: operations.activity(mirrorID: repo.id),
            staleAfter: Date().addingTimeInterval(-MirrorListProjection.staleInterval)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            RepoDetailView(repo: repo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(item: $pendingConfirmation, content: confirmationAlert)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.xl) {
                repositoryIdentity
                Spacer(minLength: DesignTokens.Spacing.md)
                actionBar
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                repositoryIdentity
                actionBar
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
        .padding(.top, DesignTokens.Spacing.paneHeaderTop)
        .padding(.bottom, DesignTokens.Spacing.paneHeaderBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repositoryIdentity: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietPressButtonStyle())
            .foregroundStyle(.secondary)
            .help(String.loc("Back to Mirrors"))
            .accessibilityLabel(String.loc("Back to Mirrors"))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(repo.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("mirror-detail.title")

                    RepoDetailStatusBadge(status: row.status)
                }

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(row.sourceLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(row.targetLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.additionalTargetCount > 0 {
                        Text(verbatim: "+\(row.additionalTargetCount)")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            primaryActionButton

            Menu {
                Button(action: onEdit) {
                    Label(String.loc("Edit Mirror…"), systemImage: "slider.horizontal.3")
                }

                if scheduleState.showsPauseToggle {
                    Button {
                        management.toggleScheduledSyncPause(mirrorID: repo.id)
                    } label: {
                        Label(scheduleToggleTitle, systemImage: scheduleState.toggleSymbolName)
                    }
                }

                Button {
                    operations.triggerVerify(mirrorID: repo.id)
                } label: {
                    Label(String.loc("Verify Now"), systemImage: "checkmark.shield")
                }
                .disabled(isSyncBusy || isVerifying)

                Button {
                    workspace.requestOpenSyncLog(mirrorID: repo.id)
                } label: {
                    Label(String.loc("Open Sync Log"), systemImage: "doc.text.magnifyingglass")
                }

                if hasLocalCache {
                    Divider()

                    Button {
                        pendingConfirmation = .clearLocalCache
                    } label: {
                        Label(String.loc("Clear Local Cache…"), systemImage: "externaldrive.badge.minus")
                    }
                    .disabled(isSyncBusy || cache.isCleaning)
                }

                Divider()

                Button(role: .destructive) {
                    pendingConfirmation = .deleteRepository
                } label: {
                    Label(String.loc("Delete Mirror…"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String.loc("More Options"))
            .accessibilityLabel(String.loc("More Options"))
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        Group {
            if primaryActionIsCancellation {
                Button(action: performPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionSymbol)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: performPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionSymbol)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityIdentifier("mirror-detail.primary-action")
    }

    private var primaryActionTitle: String {
        switch presentation.primaryAction {
        case .completeSetup: String.loc("Complete Setup")
        case .startFirstSync: String.loc("Start First Sync")
        case .cancelQueuedRun: String.loc("Cancel Queued Run")
        case .cancelSync: String.loc("Cancel Sync")
        case .cancelVerification: String.loc("Cancel Verification")
        case .reconnectCredential: String.loc("Reconnect Credential")
        case .reviewChanges: String.loc("Review Changes")
        case .reviewDivergence: String.loc("Review Divergence")
        case .retry: String.loc("Retry")
        case .syncNow: String.loc("Sync Now")
        case .resumeSchedule: String.loc("Resume Scheduled Sync")
        }
    }

    private var primaryActionSymbol: String {
        switch presentation.primaryAction {
        case .completeSetup: "slider.horizontal.3"
        case .startFirstSync, .retry, .syncNow: "arrow.triangle.2.circlepath"
        case .cancelQueuedRun, .cancelSync, .cancelVerification: "stop.fill"
        case .reconnectCredential: "key"
        case .reviewChanges: "exclamationmark.shield"
        case .reviewDivergence: "arrow.triangle.branch"
        case .resumeSchedule: "play.fill"
        }
    }

    private var primaryActionIsCancellation: Bool {
        switch presentation.primaryAction {
        case .cancelQueuedRun, .cancelSync, .cancelVerification:
            true
        default:
            false
        }
    }

    private func performPrimaryAction() {
        switch presentation.primaryAction {
        case .completeSetup:
            onEdit()
        case .startFirstSync, .retry, .syncNow:
            operations.triggerSync(mirrorID: repo.id)
        case .cancelQueuedRun, .cancelSync:
            operations.cancelSync(mirrorID: repo.id)
        case .cancelVerification:
            operations.cancelVerify(mirrorID: repo.id)
        case .reconnectCredential:
            workspace.requestEditCredentials(mirrorID: repo.id)
        case .reviewChanges, .reviewDivergence:
            workspace.requestOpenSyncLog(mirrorID: repo.id)
        case .resumeSchedule:
            management.toggleScheduledSyncPause(mirrorID: repo.id)
        }
    }

    private var scheduleToggleTitle: String {
        scheduleState.isPaused
            ? String.loc("Resume Scheduled Sync")
            : String.loc("Pause Scheduled Sync")
    }

    private func confirmationAlert(_ confirmation: RepositoryConfirmation) -> Alert {
        switch confirmation {
        case .clearLocalCache:
            Alert(
                title: Text(String.loc("Clear Local Cache")),
                message: Text(
                    String(
                        format: String.loc("Clear the local cache for “%@”? It will be rebuilt automatically during the next sync. Source and target repositories are not affected."),
                        repo.name
                    )
                ),
                primaryButton: .destructive(Text(String.loc("Clear Cache"))) {
                    Task { await cache.clean(mirrorID: repo.id) }
                },
                secondaryButton: .cancel(Text(String.loc("Cancel")))
            )

        case .deleteRepository:
            Alert(
                title: Text(String.loc("Delete Mirror")),
                message: Text(
                    String(
                        format: String.loc("Delete “%@”? The local mirror cache will also be deleted. This action cannot be undone."),
                        repo.name
                    )
                ),
                primaryButton: .destructive(Text(String.loc("Delete"))) {
                    Task { await deleteRepository() }
                },
                secondaryButton: .cancel(Text(String.loc("Cancel")))
            )
        }
    }

    private func deleteRepository() async {
        guard await security.authorize(.deleteRepository) else { return }
        management.delete(mirrorID: repo.id)
        onBack()
    }
}

private enum RepositoryConfirmation: Int, Identifiable {
    case clearLocalCache
    case deleteRepository

    var id: Int { rawValue }
}

private struct RepoDetailStatusBadge: View {
    let status: MirrorSummaryStatusKind

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(status.title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(status == .failed ? tint : Color.secondary)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxxs)
        .background(DesignTokens.Surface.chipFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.chip,
                style: .continuous
            )
        )
    }

    private var tint: Color {
        switch status {
        case .succeeded:
            DesignTokens.StatusColor.success
        case .failed:
            DesignTokens.StatusColor.escalatedFailure
        case .syncing, .queued, .notSynced:
            Color.secondary
        }
    }
}
