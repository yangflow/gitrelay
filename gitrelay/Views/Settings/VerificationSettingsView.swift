import SwiftUI

struct VerificationSettingsView: View {
    @Environment(AppPreferencesModel.self) private var preferences
    @Environment(MirrorSchedulingController.self) private var scheduling
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorLibraryModel.self) private var library

    var body: some View {
        Form {
            Section {
                Picker(String.loc("Verification Frequency"), selection: frequencyBinding) {
                    ForEach(VerificationFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Stepper(value: sampleSizeBinding, in: VerificationPreferences.sampleSizeRange) {
                    Text(String(format: String.loc("Sample %lld repositories each time"), preferences.verification.sampleSize))
                }

                if let next = scheduling.nextVerificationFireDate() {
                    LabeledContent(String.loc("Next Sample")) {
                        Text(next, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String.loc("Backup Integrity Verification"))
            } footer: {
                Text(String.loc("Periodically compare the src/dst tip SHA and tree hash for a random sample of repositories. Mismatches are marked as content divergence."))
            }

            Section {
                Button(String.loc("Verify a Sample Now")) {
                    let sample = VerificationSampler.sample(
                        from: library.plans,
                        count: preferences.verification.sampleSize
                    )
                    sample.forEach { operations.triggerVerify(mirrorID: $0.id) }
                }
                .disabled(library.mirrors.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: DesignTokens.Layout.settingsMinWidth, minHeight: DesignTokens.Layout.verificationSettingsMinHeight)
        .gitRelayChrome(.sheet)
    }

    private var frequencyBinding: Binding<VerificationFrequency> {
        Binding(
            get: { preferences.verification.frequency },
            set: { newValue in
                var prefs = preferences.verification
                prefs.frequency = newValue
                preferences.updateVerification(prefs)
            }
        )
    }

    private var sampleSizeBinding: Binding<Int> {
        Binding(
            get: { preferences.verification.sampleSize },
            set: { newValue in
                var prefs = preferences.verification
                prefs.sampleSize = VerificationPreferences.clampedSampleSize(newValue)
                preferences.updateVerification(prefs)
            }
        )
    }
}
