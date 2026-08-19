import SwiftUI

struct FrequencyPickerView: View {
    @Binding var frequency: SyncFrequency

    var body: some View {
        Picker("Sync Frequency", selection: $frequency) {
            ForEach(SyncFrequency.allCases) { freq in
                Text(freq.rawValue).tag(freq)
            }
        }
        .pickerStyle(.menu)
    }
}
