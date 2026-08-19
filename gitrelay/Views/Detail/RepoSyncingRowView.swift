import SwiftUI

struct RepoSyncingRowView: View {
    let statusTitle: String
    let latestLogLine: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.callout)
                if let latestLogLine {
                    Text(latestLogLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}
