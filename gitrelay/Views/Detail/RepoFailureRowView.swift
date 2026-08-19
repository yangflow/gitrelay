import SwiftUI

struct RepoFailureRowView: View {
    let message: String
    let lastSyncedAt: Date?
    let lastSuccessfulSyncedAt: Date?
    let consecutiveFailureCount: Int
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Last Sync Failed")
                    .font(.callout)
                    .fontWeight(.medium)
                if consecutiveFailureCount > 0 {
                    Text("\(consecutiveFailureCount) consecutive failures")
                        .font(.caption)
                        .foregroundStyle(consecutiveFailureCount >= 3 ? .red : .secondary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let lastSuccessfulSyncedAt {
                    Text("Last success: \(lastSuccessfulSyncedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastSyncedAt {
                    Text(lastSyncedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        }
    }
}
