import SwiftUI

/// One row of the 设置 → 安全 account list: the account's name and host, when it
/// was last used, and 测试.
///
/// The result of a check replaces the credential line in place, so the answer
/// stays on the row it belongs to instead of becoming a banner.
struct ProviderAccountRowView: View {
    let summary: ProviderAccountSummary
    let outcome: ProviderTokenTestOutcome?
    let isTesting: Bool
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: summary.provider.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(summary.label)
                statusLine
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            Text(summary.lastUsedText())
                .font(.caption)
                .foregroundStyle(.secondary)

            if isTesting {
                ProgressView()
                    .controlSize(.small)
            }

            Button(String(localized: "Test"), action: onTest)
                .disabled(isTesting || !summary.hasToken)
                .help(String(localized: "Ask \(summary.provider.shortName) whether the saved token still works"))
        }
    }

    private var statusLine: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(summary.hostText)
            Text(verbatim: "·")
            if let outcome {
                Image(systemName: outcome.symbolName)
                Text(outcome.rowText)
            } else {
                Text(summary.credentialText)
            }
        }
        .font(.caption)
        .foregroundStyle(outcome.map { $0.tone.color } ?? DesignTokens.StatusColor.unknown)
    }
}

private extension ProviderTokenTestTone {
    var color: Color {
        switch self {
        case .ok:
            DesignTokens.StatusColor.success
        case .warning:
            DesignTokens.StatusColor.warning
        case .error:
            DesignTokens.StatusColor.error
        case .neutral:
            DesignTokens.StatusColor.unknown
        }
    }
}
