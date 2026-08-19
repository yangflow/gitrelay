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
                Toggle("Enable sync failure notifications", isOn: $store.preferences.notificationsEnabled)

                Toggle("Notify on the first failure", isOn: $store.preferences.notifyOnFirstFailure)
                    .disabled(!store.preferences.notificationsEnabled)

                Stepper(
                    value: $store.preferences.consecutiveFailureThreshold,
                    in: 1...20
                ) {
                    Text("Consecutive failure threshold: \(store.preferences.consecutiveFailureThreshold)")
                }
                .disabled(!store.preferences.notificationsEnabled)

                Picker("Notification Level", selection: $store.preferences.interruptionLevel) {
                    ForEach(NotificationInterruptionPreference.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .disabled(!store.preferences.notificationsEnabled)

                Text(store.preferences.interruptionLevel.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Failure Notifications")
            } footer: {
                Text("Notify only on the first failure (optional), or when consecutive failures reach the threshold and its multiples, to avoid alerts from brief network interruptions. Notifications are deferred while Focus is on and combined into a summary afterward.")
            }

            Section {
                Toggle("Pause scheduled sync in Low Power Mode", isOn: $store.preferences.pauseOnLowPowerMode)
                Toggle("Pause scheduled sync on expensive networks or hotspots", isOn: $store.preferences.pauseOnExpensiveNetwork)

                if let reason = environmentMonitor.pauseReason(using: store.preferences.pausePolicy) {
                    Label(reason.displayMessage, systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            } header: {
                Text("Scheduled Sync Pausing")
            } footer: {
                Text("This affects only syncs triggered automatically by frequency. Manual sync and instant webhook sync are unaffected.")
            }

            Section {
                Toggle("Enable local webhook listener", isOn: $webhookStore.preferences.listenerEnabled)

                if webhookStore.preferences.listenerEnabled {
                    if let port = appVM.webhookListenPort {
                        LabeledContent("Listening Address") {
                            Text("127.0.0.1:\(port)")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        Text(appVM.isWebhookListenerRunning ? String(localized: "Binding port…") : String(localized: "Listener Not Running"))
                            .foregroundStyle(.secondary)
                    }

                    Picker("External Access", selection: $webhookStore.preferences.exposureMode) {
                        ForEach(WebhookExposureMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Text(webhookStore.preferences.exposureMode.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if webhookStore.preferences.exposureMode != .off {
                        TextField("Public Base URL (Optional)", text: $webhookStore.preferences.publicBaseURL)
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
                                Text("Relay mode is a configuration example only. A Worker or GitHub App can forward to the local listener using long polling; this version does not deploy a hosted service.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .off:
                                EmptyView()
                            }
                        }
                    }
                }
            } header: {
                Text("Instant Webhook Sync")
            } footer: {
                Text("Off by default. When enabled, a random port on 127.0.0.1 accepts POST /hook/<id>. The HMAC secret is stored only in Keychain. Cloudflare and Tailscale are optional runtime dependencies that must be installed locally.")
            }

            Section {
                Button("Restore Defaults") {
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
                available ? String(localized: "\(tool) detected") : String(localized: "\(tool) not detected (you can install it manually)"),
                systemImage: available ? "checkmark.circle" : "questionmark.circle"
            )
            .font(.caption)
            .foregroundStyle(available ? .green : .secondary)

            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("Copy") {
                    ClipboardService.copy(command)
                }
                .font(.caption)
            }
        }
    }
}
