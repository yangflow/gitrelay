import SwiftUI

struct SyncLogView: View {
    let records: [SyncRecord]

    var body: some View {
        Group {
            if records.isEmpty {
                Text(String.loc("No Records"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
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
                .gitRelayPanelSurface(fill: DesignTokens.Surface.logFill)
            }
        }
    }
}
