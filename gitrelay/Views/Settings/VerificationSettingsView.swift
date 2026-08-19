import SwiftUI

struct VerificationSettingsView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        Form {
            Section {
                Picker("校验频率", selection: frequencyBinding) {
                    ForEach(VerificationFrequency.allCases) { frequency in
                        Text(frequency.rawValue).tag(frequency)
                    }
                }

                Stepper(value: sampleSizeBinding, in: VerificationPreferences.sampleSizeRange) {
                    Text("每次抽样 \(appVM.verificationPreferences.sampleSize) 个仓库")
                }

                if let next = appVM.nextVerificationFireDate() {
                    LabeledContent("下次抽样") {
                        Text(next, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("备份可信度校验")
            } footer: {
                Text("周期性对随机抽样的仓库执行 src/dst tip SHA 与 tree hash 比对。不一致时标记为内容分歧。")
            }

            Section {
                Button("立即抽样校验") {
                    appVM.triggerVerifySampleNow()
                }
                .disabled(appVM.repos.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 240)
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
