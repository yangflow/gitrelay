import SwiftUI

struct SyncLogView: View {
    let records: [SyncRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("同步日志")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if records.isEmpty {
                Text("暂无记录")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(records) { record in
                                RecordSection(record: record)
                            }
                        }
                        .id("bottom")
                    }
                    .onChange(of: records.count) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .frame(maxHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
    }
}

private struct RecordSection: View {
    let record: SyncRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.succeeded ? .green : .red)
                    .font(.caption2)
                Text(record.startedAt.shortFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            ForEach(record.logLines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}
