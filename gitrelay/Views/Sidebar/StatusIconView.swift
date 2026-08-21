import SwiftUI

struct StatusIconView: View {
    let status: SyncStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Group {
            switch status {
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(DesignTokens.StatusColor.unknown)
            case .idle:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.StatusColor.idle)
            case .ahead(let n):
                HStack(spacing: DesignTokens.Spacing.xxxs) {
                    Text("\(n)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.ahead)
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(DesignTokens.StatusColor.ahead)
                }
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(DesignTokens.StatusColor.syncing)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 360 : 0)))
                    .opacity(reduceMotion && isAnimating ? 0.5 : 1)
                    .task {
                        if reduceMotion {
                            isAnimating = true
                        } else {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                isAnimating = true
                            }
                        }
                    }
                    .onDisappear { isAnimating = false }
            case .diverged:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.StatusColor.diverged)
                    .help("Backup content differs from the source repository")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.StatusColor.failed)
            }
        }
        .font(.callout)
    }
}
