import SwiftUI

struct TokenScopeBannerView: View {
    let validation: TokenScopeValidation?

    var body: some View {
        if let validation {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: validation.isFullyAuthorized
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                Text(validation.bannerText)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(
                validation.isFullyAuthorized
                    ? DesignTokens.StatusColor.success
                    : DesignTokens.StatusColor.warning
            )
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.popoverChromeVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                validation.isFullyAuthorized
                    ? DesignTokens.Surface.bannerSuccessFill
                    : DesignTokens.Surface.bannerWarningFill
            )
        }
    }
}
