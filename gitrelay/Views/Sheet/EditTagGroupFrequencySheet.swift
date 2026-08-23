import SwiftUI

struct EditTagGroupFrequencySheet: View {
    let tag: String?
    let repoCount: Int

    @Environment(MirrorManagementController.self) private var management
    @Environment(\.dismiss) private var dismiss

    @State private var frequency: SyncFrequency = .manual

    private var groupTitle: String {
        tag ?? String.loc("Untagged")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String.loc("Edit Group Sync Frequency"))
                    .font(.headline)
                Spacer()
            }
            .gitRelaySheetHeaderPadding()

            Divider()

            Form {
                Section {
                    Text(String(format: String.loc("Set the sync frequency for all %lld repositories in “%@” to:"), repoCount, groupTitle))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    FrequencyPickerView(frequency: $frequency)
                } header: {
                    Text(String.loc("Sync Frequency"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(String.loc("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(String.loc("Save")) {
                    management.updateFrequency(matchingTag: tag, frequency: frequency)
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
            frequency = management.mirrors(matchingTag: tag).first?.frequency ?? .manual
        }
    }
}
