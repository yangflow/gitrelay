import SwiftUI

struct SettingsView: View {
    @Environment(NotificationPreferencesStore.self) private var preferencesStore
    @Environment(SyncEnvironmentMonitor.self) private var environmentMonitor

    var body: some View {
        @Bindable var store = preferencesStore
        Form {
            Section {
                Toggle("启用同步失败通知", isOn: $store.preferences.notificationsEnabled)

                Toggle("首次失败时通知", isOn: $store.preferences.notifyOnFirstFailure)
                    .disabled(!store.preferences.notificationsEnabled)

                Stepper(
                    value: $store.preferences.consecutiveFailureThreshold,
                    in: 1...20
                ) {
                    Text("连续失败阈值：\(store.preferences.consecutiveFailureThreshold) 次")
                }
                .disabled(!store.preferences.notificationsEnabled)

                Picker("通知级别", selection: $store.preferences.interruptionLevel) {
                    ForEach(NotificationInterruptionPreference.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .disabled(!store.preferences.notificationsEnabled)

                Text(store.preferences.interruptionLevel.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("失败通知")
            } footer: {
                Text("仅在首次失败（可选）或连续失败达到阈值（及其倍数）时推送，避免短暂网络抖动刷屏。专注模式开启时会暂存，解除后发送聚合摘要。")
            }

            Section {
                Toggle("低电量模式时暂停计划同步", isOn: $store.preferences.pauseOnLowPowerMode)
                Toggle("昂贵网络 / 热点时暂停计划同步", isOn: $store.preferences.pauseOnExpensiveNetwork)

                if let reason = environmentMonitor.pauseReason(using: store.preferences.pausePolicy) {
                    Label(reason.displayMessage, systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            } header: {
                Text("计划同步暂停")
            } footer: {
                Text("仅影响按频率自动触发的同步；你仍可随时手动同步。")
            }

            Section {
                Button("恢复默认设置") {
                    store.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .padding()
    }
}
