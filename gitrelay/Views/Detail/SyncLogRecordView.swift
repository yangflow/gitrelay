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

            if !record.targetResults.isEmpty {
                if !record.logLines.isEmpty {
                    logBlock(title: "源", lines: record.logLines)
                }
                ForEach(record.targetResults) { result in
                    targetBlock(result)
                }
            } else {
                ForEach(record.logLines, id: \.self) { line in
                    logLine(line)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func targetBlock(_ result: TargetSyncResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(result.succeeded ? .green : .red)
                Text(result.targetURL)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.top, 4)

            logBlock(title: nil, lines: result.logLines)
        }
    }

    @ViewBuilder
    private func logBlock(title: String?, lines: [String]) {
        if let title {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        ForEach(lines, id: \.self) { line in
            logLine(line)
        }
    }

    private func logLine(_ line: String) -> some View {
        Text(line)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }

    private var isDivergenceRecord: Bool {
        record.logLines.contains { $0.contains("内容分歧") || $0.contains("Divergence detected") }
            || record.targetResults.contains { ($0.error ?? "").contains("内容分歧") }
    }

    private var iconName: String {
        isDivergenceRecord ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
    }

    private var iconColor: Color {
        isDivergenceRecord ? .yellow : .red
    }
}
