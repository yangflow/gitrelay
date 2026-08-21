import SwiftUI

struct RepoFailureNextStepActionsView: View {
    let nextStep: RepoFailureNextStep
    var compact: Bool = false
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void

    var body: some View {
        if nextStep == .none {
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
                        Button(String(localized: "Re-enter credentials"), action: onReenterCredentials)
                            .buttonStyle(.borderless)
                            .controlSize(compact ? .mini : .small)
                    }
                    if nextStep.showsOpenLog {
                        Button(String(localized: "Open Log"), action: onOpenLog)
                            .buttonStyle(.borderless)
                            .controlSize(compact ? .mini : .small)
                    }
                }
            }
        }
    }
}
