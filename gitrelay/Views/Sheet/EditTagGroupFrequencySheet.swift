import SwiftUI

struct EditTagGroupFrequencySheet: View {
    let tag: String?
    let repoCount: Int

    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss

    @State private var frequency: SyncFrequency = .manual

    private var groupTitle: String {
        tag ?? "未标记"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑组内同步频率")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section {
                    Text("将「\(groupTitle)」组内 \(repoCount) 个仓库的同步频率统一设为：")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    FrequencyPickerView(frequency: $frequency)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("保存") {
                    appVM.updateFrequency(matchingTag: tag, frequency: frequency)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 420)
        .onAppear {
            frequency = appVM.repos(matchingTag: tag).first?.frequency ?? .manual
        }
    }
}
