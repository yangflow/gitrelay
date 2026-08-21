import SwiftUI

struct VerificationSettingsView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        Form {
            Section {
                Picker("Verification Frequency", selection: frequencyBinding) {
                    ForEach(VerificationFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Stepper(value: sampleSizeBinding, in: VerificationPreferences.sampleSizeRange) {
                    Text("Sample \(appVM.verificationPreferences.sampleSize) repositories each time")
                }

                if let next = appVM.nextVerificationFireDate() {
                    LabeledContent("Next Sample") {
                        Text(next, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Backup Integrity Verification")
            } footer: {
                Text("Periodically compare the src/dst tip SHA and tree hash for a random sample of repositories. Mismatches are marked as content divergence.")
            }

            Section {
                Button("Verify a Sample Now") {
                    appVM.triggerVerifySampleNow()
                }
                .disabled(appVM.repos.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: DesignTokens.Layout.settingsMinWidth, minHeight: DesignTokens.Layout.verificationSettingsMinHeight)
        .gitRelayChrome(.sheet)
    }

    private var frequencyBinding: Binding<VerificationFrequency> {
        Binding(
            get: { appVM.verificationPreferences.frequency },
            set: { newValue in
                var prefs = appVM.verificationPreferences
                prefs.frequency = newValue
                appVM.updateVerificationPreferences(prefs)
            }
        )
    }

    private var sampleSizeBinding: Binding<Int> {
        Binding(
            get: { appVM.verificationPreferences.sampleSize },
            set: { newValue in
                var prefs = appVM.verificationPreferences
                prefs.sampleSize = VerificationPreferences.clampedSampleSize(newValue)
                appVM.updateVerificationPreferences(prefs)
            }
        )
    }
}
