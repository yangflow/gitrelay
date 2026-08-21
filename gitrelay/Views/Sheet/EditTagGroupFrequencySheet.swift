import SwiftUI

struct EditTagGroupFrequencySheet: View {
    let tag: String?
    let repoCount: Int

    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss

    @State private var frequency: SyncFrequency = .manual

    private var groupTitle: String {
        tag ?? String(localized: "Untagged")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Edit Group Sync Frequency"))
                    .font(.headline)
                Spacer()
            }
            .gitRelaySheetHeaderPadding()

            Divider()

            Form {
                Section {
                    Text(String(localized: "Set the sync frequency for all \(repoCount) repositories in “\(groupTitle)” to:"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    FrequencyPickerView(frequency: $frequency)
                } header: {
                    Text(String(localized: "Sync Frequency"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(String(localized: "Save")) {
                    appVM.updateFrequency(matchingTag: tag, frequency: frequency)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: 420)
        .gitRelayChrome(.sheet)
        .onAppear {
            frequency = appVM.repos(matchingTag: tag).first?.frequency ?? .manual
        }
    }
}
