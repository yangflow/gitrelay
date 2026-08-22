import SwiftUI

struct FrequencyPickerView: View {
    @Binding var frequency: SyncFrequency

    var body: some View {
        Picker(String.loc("Sync Frequency"), selection: $frequency) {
            ForEach(SyncFrequency.allCases) { freq in
                Text(freq.displayName).tag(freq)
            }
        }
        .pickerStyle(.menu)
    }
}
