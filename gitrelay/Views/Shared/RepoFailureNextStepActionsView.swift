import SwiftUI

struct RepoFailureNextStepActionsView: View {
    let nextStep: RepoFailureNextStep
    var compact: Bool = false
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void
    /// 复制这次失败: absent where there is no failed run to copy (or no
    /// clipboard affordance, such as the menu-bar row).
    var onCopyFailure: (() -> Void)?

    @State private var didCopy = false

    var body: some View {
        if nextStep == .none, onCopyFailure == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                if let caption = nextStep.missingRepositoryCaption {
                    Text(caption)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(DesignTokens.StatusColor.failed)
                        .lineLimit(compact ? 2 : nil)
                }

                if let hint = nextStep.missingGitLFSInstallHint {
                    Text(hint)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(DesignTokens.StatusColor.pause)
                        .lineLimit(compact ? 2 : nil)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    if nextStep.showsReenterCredentials {
                        Button(String.loc("Re-enter credentials"), action: onReenterCredentials)
                            .buttonStyle(.borderless)
                            .controlSize(compact ? .mini : .small)
                    }
                    if nextStep.showsOpenLog {
                        Button(String.loc("Open Log"), action: onOpenLog)
                            .buttonStyle(.borderless)
                            .controlSize(compact ? .mini : .small)
                    }
                    if let onCopyFailure {
                        Button(copyTitle) {
                            onCopyFailure()
                            didCopy = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(compact ? .mini : .small)
                        .help(String.loc("Copies the failed run's log with credentials redacted"))
                    }
                }
            }
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        }
    }

    private var copyTitle: String {
        didCopy ? String.loc("Copied") : String.loc("Copy this failure")
    }
}
