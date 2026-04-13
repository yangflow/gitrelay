import SwiftUI

struct RepoSyncingRowView: View {
    let latestLogLine: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在同步...")
                    .font(.callout)
                if let latestLogLine {
                    Text(latestLogLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("取消", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}
