import SwiftUI

struct RepoDivergedRowView: View {
    let detail: String
    let lastVerifiedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.diverged)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String.loc("Backup content may have diverged from the source repository"))
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let lastVerifiedAt {
                    Text(String(format: String.loc("Last verified: %@"), lastVerifiedAt.formatted(.relative(presentation: .named))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
