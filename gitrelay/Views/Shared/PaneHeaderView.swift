import SwiftUI

/// Title block at the top of every right-pane destination (仓库 / 队列 / 账号 / 设置).
struct PaneHeaderView<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            accessory()
        }
        .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
        .padding(.top, DesignTokens.Spacing.paneHeaderTop)
        .padding(.bottom, DesignTokens.Spacing.paneHeaderBottom)
    }
}

extension PaneHeaderView where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Centered secondary copy used by panes with nothing to show yet.
struct PaneEmptyStateView: View {
    let systemImage: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxl)
    }
}
