import SwiftUI

struct StatusIconView: View {
    let status: SyncStatus

    @State private var isAnimating = false

    var body: some View {
        Group {
            switch status {
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            case .idle:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .ahead(let n):
                HStack(spacing: 2) {
                    Text("\(n)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                }
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
                    .onDisappear { isAnimating = false }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.system(size: 14))
    }
}
