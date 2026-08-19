import SwiftUI

struct SyncLogRecordView: View {
    let record: SyncRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Image(systemName: record.succeeded ? "checkmark.circle.fill" : iconName)
                    .foregroundStyle(record.succeeded ? .green : iconColor)
                    .font(.caption)
                Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            ForEach(record.logLines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var isDivergenceRecord: Bool {
        record.logLines.contains { $0.contains("内容分歧") || $0.contains("Divergence detected") }
    }

    private var iconName: String {
        isDivergenceRecord ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
    }

    private var iconColor: Color {
        isDivergenceRecord ? .yellow : .red
    }
}
