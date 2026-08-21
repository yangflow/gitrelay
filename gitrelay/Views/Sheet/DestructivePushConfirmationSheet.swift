import SwiftUI

struct DestructivePushConfirmationSheet: View {
    let repoName: String
    let targetURL: String?
    let plan: DestructivePushPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.StatusColor.diverged)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                    Text("Confirm Destructive Mirror Push")
                        .font(.headline)
                    Text(repoName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let targetURL {
                        Text(targetURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(plan.confirmationPrompt)
                        .font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.sheetContent)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    if !plan.deletedRefs.isEmpty {
                        refSection(
                            title: "Delete \(plan.deletedRefs.count) refs",
                            refs: plan.deletedRefs,
                            symbol: "trash",
                            tint: DesignTokens.StatusColor.error,
                            fill: DesignTokens.Surface.destructiveFill
                        )
                    }
                    if !plan.forcedUpdateRefs.isEmpty {
                        refSection(
                            title: "Force-update \(plan.forcedUpdateRefs.count) refs",
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

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Button("Continue", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.StatusColor.warning)
                    .keyboardShortcut(.return)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: 480)
        .frame(minHeight: 280)
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
            .background(fill)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DesignTokens.CornerRadius.banner,
                    style: .continuous
                )
            )
        }
    }
}
