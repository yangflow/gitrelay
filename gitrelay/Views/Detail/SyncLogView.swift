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
                                SyncLogRecordView(record: record)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                    }
                    .onChange(of: records.count) {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
        }
    }
}
