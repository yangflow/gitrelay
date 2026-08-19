import SwiftUI

struct SettingsView: View {
    @Environment(NotificationPreferencesStore.self) private var preferencesStore
    @Environment(SyncEnvironmentMonitor.self) private var environmentMonitor
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        @Bindable var store = preferencesStore
        @Bindable var webhookStore = appVM.webhookPreferences
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
                Text("仅影响按频率自动触发的同步；手动同步与 webhook 即时同步不受影响。")
            }

            Section {
                Toggle("启用本机 Webhook 监听", isOn: $webhookStore.preferences.listenerEnabled)

                if webhookStore.preferences.listenerEnabled {
                    if let port = appVM.webhookListenPort {
                        LabeledContent("监听地址") {
                            Text("127.0.0.1:\(port)")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        Text(appVM.isWebhookListenerRunning ? "正在绑定端口…" : "监听未运行")
                            .foregroundStyle(.secondary)
                    }

                    Picker("外网暴露", selection: $webhookStore.preferences.exposureMode) {
                        ForEach(WebhookExposureMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Text(webhookStore.preferences.exposureMode.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if webhookStore.preferences.exposureMode != .off {
                        TextField("公共 Base URL（可选）", text: $webhookStore.preferences.publicBaseURL)
                            .font(.system(.body, design: .monospaced))

                        if let port = appVM.webhookListenPort {
                            switch webhookStore.preferences.exposureMode {
                            case .cloudflareTunnel:
                                tunnelHint(
                                    available: WebhookTunnelToolDetector.isCloudflaredAvailable(),
                                    tool: "cloudflared",
                                    command: WebhookURLTemplate.cloudflaredCommand(port: port)
                                )
                            case .tailscaleFunnel:
                                tunnelHint(
                                    available: WebhookTunnelToolDetector.isTailscaleAvailable(),
                                    tool: "tailscale",
                                    command: WebhookURLTemplate.tailscaleFunnelCommand(port: port)
                                )
                            case .relaySketch:
                                Text("中继模式仅作配置示意：可用 Worker/GitHub App 长轮询转发到本机监听端口，本版本不部署托管服务。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .off:
                                EmptyView()
                            }
                        }
                    }
                }
            } header: {
                Text("Webhook 即时同步")
            } footer: {
                Text("默认关闭。开启后在 127.0.0.1 随机端口接收 POST /hook/<id>；HMAC 密钥仅存 Keychain。Cloudflare / Tailscale 为可选运行时依赖，需你本机已安装。")
            }

            Section {
                Button("恢复默认设置") {
                    store.resetToDefaults()
                    webhookStore.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 420)
        .padding()
    }

    @ViewBuilder
    private func tunnelHint(available: Bool, tool: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                available ? "已检测到 \(tool)" : "未检测到 \(tool)（可手动安装后使用）",
                systemImage: available ? "checkmark.circle" : "questionmark.circle"
            )
            .font(.caption)
            .foregroundStyle(available ? .green : .secondary)

            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("复制") {
                    ClipboardService.copy(command)
                }
                .font(.caption)
            }
        }
    }
}
