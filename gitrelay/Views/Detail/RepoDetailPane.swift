import SwiftUI

/// Repository detail reached from a pair-table row: a back link to 仓库, the
/// repository name with its 同步 / 暂停 toolbar, then the ``RepoDetailView`` body.
struct RepoDetailPane: View {
    @Environment(AppViewModel.self) private var appVM

    let repo: RepoConfig
    let onBack: () -> Void

    private var scheduleState: RepoScheduleState {
        RepoScheduleState.make(repo: repo)
    }

    /// A pair already syncing, queued for a slot, or verifying has nothing to
    /// start; the status section owns cancelling.
    private var isBusy: Bool {
        appVM.inProgressSyncIDs.contains(repo.id)
            || appVM.inProgressVerifyIDs.contains(repo.id)
            || appVM.statuses[repo.id] == .queued
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Button(action: onBack) {
                    Label(
                        MainSidebarItem.repositories.title,
                        systemImage: "chevron.left"
                    )
                    .font(.callout)
                }
                .buttonStyle(QuietPressButtonStyle())
                .foregroundStyle(.secondary)
                .help(String.loc("Back to Repositories"))

                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                    Text(repo.name)
                        .font(.title2.weight(.semibold))

                    Spacer(minLength: DesignTokens.Spacing.sm)

                    toolbar
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.paneHeaderBottom)

            RepoDetailView(repo: repo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 同步 plus 暂停 / 恢复 for the schedule. Pausing leaves manual sync alone.
    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Button {
                appVM.triggerSync(repoID: repo.id)
            } label: {
                Label(String.loc("Sync"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isBusy)
            .help(String.loc("Sync Now"))

            if scheduleState.showsPauseToggle {
                Button {
                    appVM.toggleScheduledSyncPause(repoID: repo.id)
                } label: {
                    Label(scheduleState.toggleTitle, systemImage: scheduleState.toggleSymbolName)
                }
                .help(scheduleState.toggleHelp)
            }
        }
        .buttonStyle(QuietPressButtonStyle())
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
