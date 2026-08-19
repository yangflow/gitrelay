import SwiftUI

struct TokenScopeBannerView: View {
    let validation: TokenScopeValidation?

    var body: some View {
        if let validation {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: validation.isFullyAuthorized
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                Text(validation.bannerText)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(validation.isFullyAuthorized ? Color.green : Color.orange)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (validation.isFullyAuthorized ? Color.green : Color.orange).opacity(0.12)
            )
        }
    }
}
