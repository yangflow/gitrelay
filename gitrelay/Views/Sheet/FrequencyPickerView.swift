import SwiftUI

struct FrequencyPickerView: View {
    @Binding var frequency: SyncFrequency

    var body: some View {
        Picker("同步频率", selection: $frequency) {
            ForEach(SyncFrequency.allCases) { freq in
                Text(freq.rawValue).tag(freq)
            }
        }
        .pickerStyle(.menu)
    }
}
