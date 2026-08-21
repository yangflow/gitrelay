import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @Environment(NotificationPreferencesStore.self) private var preferencesStore
    @Environment(SecurityPreferencesStore.self) private var securityStore
    @Environment(CachePreferencesStore.self) private var cacheStore
    @Environment(AppViewModel.self) private var appVM

    @State private var limitMirrorCache = false
    @State private var mirrorCacheQuotaGB = 50
    @State private var showImportModePicker = false
    @State private var pendingImportURL: URL?
    @State private var configMessage: String?

    var body: some View {
        @Bindable var store = preferencesStore
        @Bindable var security = securityStore
        @Bindable var cache = cacheStore
        @Bindable var webhookStore = appVM.webhookPreferences
        Form {
            Section {
                Toggle(
                    String(localized: "Require Touch ID or password for sensitive actions"),
                    isOn: $security.preferences.requireBiometricForSensitive
                )
            } header: {
                Text(String(localized: "Security"))
            } footer: {
                Text("When enabled, viewing tokens in plaintext, deleting repositories, and changing a mirror target to a different host require authentication. Canceling or failing authentication aborts the action.")
            }

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
                Stepper(
                    value: $store.preferences.transientGitMaxAttempts,
                    in: 1...GitRetryPolicy.clampedMaxAttempts(100)
                ) {
                    Text(
                        String(
                            localized: "Transient network retries: \(store.preferences.transientGitMaxAttempts) attempts"
                        )
                    )
                }
            } header: {
                Text(String(localized: "Sync Retries"))
            } footer: {
                Text(String(localized: "Within a single sync, retry fetch/clone/push (and LFS) on brief network errors using 2s / 8s / 32s backoff. Total wait is capped at 3 minutes. Auth failures and local corruption are not retried."))
            }

            Section {
                Toggle("Pause scheduled sync in Low Power Mode", isOn: $store.preferences.pauseOnLowPowerMode)
                Toggle("Pause scheduled sync on expensive networks or hotspots", isOn: $store.preferences.pauseOnExpensiveNetwork)

                Toggle(String(localized: "Enable quiet hours"), isOn: quietHoursEnabledBinding)

                if store.preferences.quietHours.isEnabled {
                    DatePicker(
                        String(localized: "Quiet hours start"),
                        selection: quietHoursStartBinding,
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        String(localized: "Quiet hours end"),
                        selection: quietHoursEndBinding,
                        displayedComponents: .hourAndMinute
                    )
                    Text(String(localized: "Uses this Mac's local timezone. A window such as 23:00–07:00 wraps midnight."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let reason = appVM.scheduledSyncPauseReason {
                    Label(reason.displayMessage, systemImage: "pause.circle")
                        .foregroundStyle(DesignTokens.StatusColor.pause)
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
                Toggle(String(localized: "Limit local mirror cache size"), isOn: $limitMirrorCache)
                    .onChange(of: limitMirrorCache) { _, enabled in
                        cache.preferences.cacheQuotaGB = enabled ? mirrorCacheQuotaGB : nil
                        appVM.refreshMirrorCacheUsage()
                    }

                if limitMirrorCache {
                    Stepper(value: $mirrorCacheQuotaGB, in: 1...1000) {
                        Text(String(format: String(localized: "Cache quota: %lld GB"), mirrorCacheQuotaGB))
                    }
                    .onChange(of: mirrorCacheQuotaGB) { _, value in
                        if limitMirrorCache {
                            cache.preferences.cacheQuotaGB = value
                        }
                    }
                }

                LabeledContent(String(localized: "Current Usage")) {
                    Text(MirrorCacheFormatting.usageSummary(
                        usageBytes: appVM.mirrorCacheUsageBytes,
                        quotaGB: cache.preferences.cacheQuotaGB
                    ))
                }

                Button(String(localized: "Clean Now")) {
                    Task { await appVM.cleanMirrorCacheNow() }
                }
                .disabled(appVM.isCleaningMirrorCache)
            } header: {
                Text(String(localized: "Mirror Cache"))
            } footer: {
                Text(String(localized: "Bare clones are stored under ~/.local/share/gitrelay/mirrors/. When over quota, GitRelay runs git gc on least-recently synced mirrors first, then deletes entire clones if needed. The next sync rebuilds deleted mirrors."))
            }

            Section {
                Button(String(localized: "Export Configuration…")) {
                    exportConfiguration()
                }
                Button(String(localized: "Import Configuration…")) {
                    presentImportPanel()
                }
            } header: {
                Text(String(localized: "Configuration"))
            } footer: {
                Text(String(localized: "Export repository pairs, targets, tags, frequency, shallow/ref filters, LFS, org subscriptions, and account labels. Tokens and private keys are never written to the file. After import, repositories missing credentials are marked and stay unscheduled until you fill them in."))
            }

            Section {
                Button("Restore Defaults") {
                    store.resetToDefaults()
                    security.resetToDefaults()
                    cache.resetToDefaults()
                    webhookStore.resetToDefaults()
                    syncCacheControlsFromStore()
                    appVM.refreshMirrorCacheUsage()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: DesignTokens.Layout.settingsMinWidth, minHeight: DesignTokens.Layout.settingsMinHeight)
        .padding(DesignTokens.Spacing.settingsForm)
        .gitRelayChrome(.sheet)
        .onAppear {
            syncCacheControlsFromStore()
            appVM.refreshMirrorCacheUsage()
        }
        .alert(
            String(localized: "Import Configuration"),
            isPresented: $showImportModePicker
        ) {
            Button(String(localized: "Merge (skip existing IDs)")) {
                runImport(mode: .merge)
            }
            Button(String(localized: "Replace all"), role: .destructive) {
                runImport(mode: .replace)
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text(String(localized: "Merge keeps current repositories and skips matching IDs. Replace discards the current repository list and loads the file."))
        }
        .alert(
            String(localized: "Configuration"),
            isPresented: Binding(
                get: { configMessage != nil },
                set: { if !$0 { configMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(configMessage ?? "")
        }
    }

    private func syncCacheControlsFromStore() {
        if let quota = cacheStore.preferences.cacheQuotaGB {
            limitMirrorCache = true
            mirrorCacheQuotaGB = quota
        } else {
            limitMirrorCache = false
            mirrorCacheQuotaGB = 50
        }
    }

    private var quietHoursEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferencesStore.preferences.quietHours.isEnabled },
            set: { enabled in
                var prefs = preferencesStore.preferences
                prefs.quietHours.isEnabled = enabled
                preferencesStore.preferences = prefs
            }
        )
    }

    private var quietHoursStartBinding: Binding<Date> {
        minutesDateBinding(
            getMinutes: { preferencesStore.preferences.quietHours.startMinutes },
            setMinutes: { minutes in
                var prefs = preferencesStore.preferences
                prefs.quietHours.startMinutes = minutes
                preferencesStore.preferences = prefs
            }
        )
    }

    private var quietHoursEndBinding: Binding<Date> {
        minutesDateBinding(
            getMinutes: { preferencesStore.preferences.quietHours.endMinutes },
            setMinutes: { minutes in
                var prefs = preferencesStore.preferences
                prefs.quietHours.endMinutes = minutes
                preferencesStore.preferences = prefs
            }
        )
    }

    private func minutesDateBinding(
        getMinutes: @escaping () -> Int,
        setMinutes: @escaping (Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: getMinutes(), to: startOfDay) ?? startOfDay
            },
            set: { date in
                setMinutes(QuietHoursSettings.minutesSinceMidnight(of: date, calendar: .current))
            }
        )
    }

    private func exportConfiguration() {
        do {
            let data = try appVM.exportConfigurationData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "gitrelay-config.json"
            panel.canCreateDirectories = true
            panel.title = String(localized: "Export Configuration")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            configMessage = String(localized: "Configuration exported. Tokens and private keys were not included.")
        } catch {
            configMessage = error.localizedDescription
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = String(localized: "Import Configuration")
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingImportURL = url
        showImportModePicker = true
    }

    private func runImport(mode: ConfigImportMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        do {
            let data = try Data(contentsOf: url)
            let plan = try appVM.importConfiguration(from: data, mode: mode)
            if plan.skippedRepoCount > 0 {
                configMessage = String(
                    localized: "Imported \(plan.importedRepoCount) repositories (skipped \(plan.skippedRepoCount) existing). Repositories missing credentials are marked and will not sync until you edit them."
                )
            } else {
                configMessage = String(
                    localized: "Imported \(plan.importedRepoCount) repositories. Repositories missing credentials are marked and will not sync until you edit them."
                )
            }
        } catch {
            configMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func tunnelHint(available: Bool, tool: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Label(
                available ? String(localized: "\(tool) detected") : String(localized: "\(tool) not detected (you can install it manually)"),
                systemImage: available ? "checkmark.circle" : "questionmark.circle"
            )
            .font(.caption)
            .foregroundStyle(available ? DesignTokens.StatusColor.success : .secondary)

            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: DesignTokens.Spacing.sm)
                Button("Copy") {
                    ClipboardService.copy(command)
                }
                .font(.caption)
            }
        }
    }
}
