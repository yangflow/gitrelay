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
                Text("Edit Group Sync Frequency")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section {
                    Text("Set the sync frequency for all \(repoCount) repositories in “\(groupTitle)” to:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    FrequencyPickerView(frequency: $frequency)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
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
