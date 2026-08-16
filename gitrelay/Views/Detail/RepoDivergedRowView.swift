import SwiftUI

struct RepoDivergedRowView: View {
    let detail: String
    let lastVerifiedAt: Date?
    let isVerifying: Bool
    let onVerifyNow: () -> Void
    let onSyncNow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("备份内容可能已偏离源仓库")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let lastVerifiedAt {
                    Text("最近校验：\(lastVerifiedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Button("立即校验", action: onVerifyNow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isVerifying)
                Button("立即同步", action: onSyncNow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
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
