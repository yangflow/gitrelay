import SwiftUI

/// Shown when the destination turns out to hold a history the source does not
/// share. It explains the overwrite in plain sentences and defaults to the
/// choice that leaves the destination's branches untouched.
struct DestructivePushConfirmationSheet: View {
    let repoName: String
    let targetURL: String?
    let plan: DestructivePushPlan
    let onDecision: (DestructivePushDecision) -> Void

    private var destinationLabel: String {
        DestructivePushCopy.destinationLabel(targetURL: targetURL, fallback: repoName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(DestructivePushCopy.title)
                    .font(.headline)
                Text(repoName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(DestructivePushCopy.divergence(destinationLabel: destinationLabel, plan: plan))
                    .font(.callout)
                Text(DestructivePushCopy.overwriteExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(DestructivePushCopy.checkBranchExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gitRelaySheetHeaderPadding()

            if plan.isDestructive {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        if !plan.deletedRefs.isEmpty {
                            refSection(
                                title: String.loc("Delete \(plan.deletedRefs.count) refs"),
                                refs: plan.deletedRefs,
                                symbol: "trash",
                                tint: DesignTokens.StatusColor.error,
                                fill: DesignTokens.Surface.destructiveFill
                            )
                        }
                        if !plan.forcedUpdateRefs.isEmpty {
                            refSection(
                                title: String.loc("Force-update \(plan.forcedUpdateRefs.count) refs"),
                                refs: plan.forcedUpdateRefs,
                                symbol: "arrow.triangle.2.circlepath",
                                tint: DesignTokens.StatusColor.warning,
                                fill: DesignTokens.Surface.forceUpdateFill
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.sheetContent)
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                Button(DestructivePushCopy.cancelTitle) { onDecision(.cancel) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(DestructivePushCopy.overwriteTitle, role: .destructive) {
                    onDecision(.overwrite)
                }
                Button(DestructivePushCopy.checkBranchTitle) { onDecision(.checkBranch) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: 480)
        .frame(minHeight: 240)
        .gitRelayChrome(.sheet)
    }

    @ViewBuilder
    private func refSection(
        title: String,
        refs: [String],
        symbol: String,
        tint: Color,
        fill: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                ForEach(refs, id: \.self) { ref in
                    Text(ref)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DesignTokens.Spacing.popoverChromeVertical)
            .gitRelayPanelSurface(
                fill: fill,
                cornerRadius: DesignTokens.CornerRadius.banner
            )
        }
    }
}
