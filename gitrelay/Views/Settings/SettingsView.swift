import SwiftUI
import UniformTypeIdentifiers
import AppKit

private enum SettingsIntegrationMode: String, CaseIterable, Identifiable {
    case webhook
    case organizationDiscovery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .webhook: String.loc("Webhook")
        case .organizationDiscovery: String.loc("Organization Discovery")
        }
    }
}

private enum SettingsMaintenanceMode: String, CaseIterable, Identifiable {
    case storage
    case verification
    case configuration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .storage: String.loc("Storage")
        case .verification: String.loc("Verification")
        case .configuration: String.loc("Configuration")
        }
    }
}

struct SettingsView: View {
    @Environment(NotificationPreferencesStore.self) private var preferencesStore
    @Environment(SecurityPreferencesStore.self) private var securityStore
    @Environment(CachePreferencesStore.self) private var cacheStore
    @Environment(AppBehaviorPreferencesStore.self) private var behaviorStore
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorSchedulingController.self) private var scheduling
    @Environment(MirrorCacheController.self) private var mirrorCache
    @Environment(WebhookController.self) private var webhooks
    @Environment(MirrorManagementController.self) private var management
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(AppLanguageStore.self) private var languageStore
    @Environment(AppPreferencesModel.self) private var appPreferences

    @State private var loginItem = LoginItemController()
    @State private var limitMirrorCache = false
    @State private var mirrorCacheQuotaGB = 50
    @State private var showImportModePicker = false
    @State private var pendingImportURL: URL?
    @State private var configMessage: String?
    @State private var selectedProvider: GitProvider = .github
    @State private var integrationMode = SettingsIntegrationMode.webhook
    @State private var maintenanceMode = SettingsMaintenanceMode.storage
    @State private var selectedPane: SettingsPane?

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
                    .accessibilityIdentifier("settings-pane.\(pane.id)")
            }
            .accessibilityIdentifier("settings.sidebar")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: DesignTokens.Layout.settingsSidebarMinWidth,
                ideal: DesignTokens.Layout.settingsSidebarIdealWidth,
                max: DesignTokens.Layout.settingsSidebarMaxWidth
            )
        } detail: {
            detailForm
                .navigationTitle(activePane.title)
                .navigationSplitViewColumnWidth(
                    min: DesignTokens.Layout.settingsDetailMinWidth,
                    ideal: DesignTokens.Layout.settingsDetailIdealWidth
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: DesignTokens.Layout.settingsMinWidth,
            minHeight: DesignTokens.Layout.settingsMinHeight
        )
        .onAppear {
            selectedPane = workspace.settingsPane
            loginItem.refresh()
            syncCacheControlsFromStore()
            mirrorCache.refreshUsage()
        }
        .onChange(of: selectedPane) { _, newValue in
            guard let newValue else { return }
            workspace.settingsPane = newValue
        }
        .onChange(of: workspace.settingsPane) { _, newValue in
            guard selectedPane != newValue else { return }
            selectedPane = newValue
        }
        .alert(
            String.loc("Import Configuration"),
            isPresented: $showImportModePicker
        ) {
            Button(String.loc("Merge (skip existing IDs)")) {
                runImport(mode: .merge)
            }
            Button(String.loc("Replace all"), role: .destructive) {
                runImport(mode: .replace)
            }
            Button(String.loc("Cancel"), role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text(String.loc("Merge keeps current repositories and skips matching IDs. Replace discards the current repository list and loads the file."))
        }
        .alert(
            String.loc("Configuration"),
            isPresented: Binding(
                get: { configMessage != nil },
                set: { if !$0 { configMessage = nil } }
            )
        ) {
            Button(String.loc("OK"), role: .cancel) {}
        } message: {
            Text(configMessage ?? "")
        }
    }

    @ViewBuilder
    private var detailForm: some View {
        switch activePane {
        case .general:
            settingsForm {
                securitySections()
                languageSection()
            }
        case .connections:
            connectionsView
        case .defaultPolicies:
            settingsForm { scheduleSections() }
        case .notifications:
            settingsForm { notificationsSection() }
        case .integrations:
            integrationsView
        case .storageMaintenance:
            storageMaintenanceView
        }
    }

    private var activePane: SettingsPane {
        selectedPane ?? workspace.settingsPane
    }

    private var connectionsView: some View {
        VStack(spacing: 0) {
            ProviderSegmentedControl(
                selection: $selectedProvider,
                providers: GitProvider.allCases
            )
            .accessibilityLabel(String.loc("Provider"))
            .padding()
            ProviderAccountsView(provider: selectedProvider)
        }
    }

    private var integrationsView: some View {
        VStack(spacing: 0) {
            Picker(String.loc("Integrations"), selection: $integrationMode) {
                ForEach(SettingsIntegrationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch integrationMode {
            case .webhook:
                settingsForm { webhookSection() }
            case .organizationDiscovery:
                OrgSubscriptionSettingsView()
            }
        }
    }

    private var storageMaintenanceView: some View {
        VStack(spacing: 0) {
            Picker(String.loc("Storage & Maintenance"), selection: $maintenanceMode) {
                ForEach(SettingsMaintenanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch maintenanceMode {
            case .storage:
                settingsForm { cacheSection() }
            case .verification:
                VerificationSettingsView()
            case .configuration:
                settingsForm { configurationSections() }
            }
        }
    }

    private func settingsForm<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func securitySections() -> some View {
        @Bindable var security = securityStore
        @Bindable var behavior = behaviorStore

        Section {
            Toggle(
                String.loc("Open at Login"),
                isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )
            )

            if let message = loginItem.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.StatusColor.error)
            } else if loginItem.requiresApproval {
                Text(
                    String.loc("Open at Login needs approval in System Settings → General → Login Items.")
                )
                .font(.caption)
                .foregroundStyle(DesignTokens.StatusColor.warning)
            }

            Toggle(
                String.loc("Keep in Menu Bar when closing main window"),
                isOn: $behavior.preferences.keepInMenuBarWhenMainWindowCloses
            )
        } header: {
            Text(String.loc("Startup & Menu Bar"))
        }

        Section {
            Toggle(
                String.loc("Require Touch ID or password for sensitive actions"),
                isOn: $security.preferences.requireBiometricForSensitive
            )
        } header: {
            Text(String.loc("Security"))
        }
    }

    @ViewBuilder
    private func notificationsSection() -> some View {
        @Bindable var store = preferencesStore

        Section {
            Toggle(String.loc("Enable sync failure notifications"), isOn: $store.preferences.notificationsEnabled)

            Toggle(String.loc("Notify on the first failure"), isOn: $store.preferences.notifyOnFirstFailure)
                .disabled(!store.preferences.notificationsEnabled)

            Stepper(
                value: $store.preferences.consecutiveFailureThreshold,
                in: 1...20
            ) {
                Text(String(format: String.loc("Consecutive failure threshold: %lld"), store.preferences.consecutiveFailureThreshold))
            }
            .disabled(!store.preferences.notificationsEnabled)

            Picker(String.loc("Notification Level"), selection: $store.preferences.interruptionLevel) {
                ForEach(NotificationInterruptionPreference.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .disabled(!store.preferences.notificationsEnabled)
        } header: {
            Text(String.loc("Failure Notifications"))
        }
    }

    @ViewBuilder
    private func scheduleSections() -> some View {
        @Bindable var store = preferencesStore
        @Bindable var defaults = appPreferences.defaultPolicyStore

        Section {
            Picker(String.loc("Sync Frequency"), selection: $defaults.preferences.frequency) {
                ForEach(SyncFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }

            Picker(
                String.loc("Destructive Push Protection"),
                selection: $defaults.preferences.destructivePush
            ) {
                ForEach(DestructivePushPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker(String.loc("Git LFS"), selection: $defaults.preferences.lfsMode) {
                ForEach(LFSMirrorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Toggle(
                String.loc("Mirror Releases and Binary Assets"),
                isOn: $defaults.preferences.mirrorsReleases
            )
            Toggle(
                String.loc("Allow Instant Webhook Sync"),
                isOn: $defaults.preferences.webhookEnabled
            )
            Picker(
                String.loc("Verification Frequency"),
                selection: $defaults.preferences.verificationFrequency
            ) {
                ForEach(VerificationFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
        } header: {
            Text(String.loc("New Mirror Defaults"))
        } footer: {
            Text(String.loc("These defaults are copied into new mirrors. Existing mirrors keep their own policies."))
        }

        Section {
            Stepper(
                value: $store.preferences.transientGitMaxAttempts,
                in: 1...GitRetryPolicy.clampedMaxAttempts(100)
            ) {
                Text(
                    String(format: String.loc("Transient network retries: %lld attempts"), store.preferences.transientGitMaxAttempts)
                )
            }
        } header: {
            Text(String.loc("Sync Retries"))
        } footer: {
            Text(String.loc("Within a single sync, retry fetch/clone/push (and LFS) on brief network errors using 2s / 8s / 32s backoff. Total wait is capped at 3 minutes. Auth failures and local corruption are not retried."))
        }

        Section {
            Stepper(
                value: $store.preferences.maxConcurrentSyncs,
                in: NotificationPreferences.maxConcurrentSyncsRange
            ) {
                Text(
                    String(format: String.loc("Max concurrent syncs: %lld"), store.preferences.maxConcurrentSyncs)
                )
            }
        } header: {
            Text(String.loc("Sync Concurrency"))
        } footer: {
            Text(String.loc("Manual, webhook, and scheduled syncs share this limit. Extra requests wait until a slot is available. Waiting work is discarded when GitRelay quits."))
        }

        Section {
            Toggle(String.loc("Pause Scheduled Sync"), isOn: $store.preferences.scheduledSyncManuallyPaused)

            Toggle(String.loc("Pause scheduled sync in Low Power Mode"), isOn: $store.preferences.pauseOnLowPowerMode)
            Toggle(String.loc("Pause scheduled sync on expensive networks or hotspots"), isOn: $store.preferences.pauseOnExpensiveNetwork)

            Toggle(String.loc("Enable quiet hours"), isOn: quietHoursEnabledBinding)

            if store.preferences.quietHours.isEnabled {
                DatePicker(
                    String.loc("Quiet hours start"),
                    selection: quietHoursStartBinding,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    String.loc("Quiet hours end"),
                    selection: quietHoursEndBinding,
                    displayedComponents: .hourAndMinute
                )
                Text(String.loc("Uses this Mac's local timezone. A window such as 23:00–07:00 wraps midnight."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = scheduling.pauseReason {
                Label(reason.displayMessage, systemImage: "pause.circle")
                    .foregroundStyle(DesignTokens.StatusColor.pause)
                    .font(.callout)
            }
        } header: {
            Text(String.loc("Scheduled Sync Pausing"))
        } footer: {
            Text(String.loc("This affects only syncs triggered automatically by frequency. Manual sync and instant webhook sync are unaffected."))
        }
    }

    @ViewBuilder
    private func webhookSection() -> some View {
        @Bindable var webhookStore = webhooks.preferences

        Section {
            Toggle(String.loc("Enable local webhook listener"), isOn: $webhookStore.preferences.listenerEnabled)

            if webhookStore.preferences.listenerEnabled {
                if let port = webhooks.listenPort {
                    LabeledContent(String.loc("Listening Address")) {
                        Text(String(format: String.loc("127.0.0.1:%lld"), port))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    Text(webhooks.isListenerRunning ? String.loc("Binding port…") : String.loc("Listener Not Running"))
                        .foregroundStyle(.secondary)
                }

                Picker(String.loc("External Access"), selection: $webhookStore.preferences.exposureMode) {
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

                    if let port = webhooks.listenPort {
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
                            Text(String.loc("Relay mode is a configuration example only. A Worker or GitHub App can forward to the local listener using long polling; this version does not deploy a hosted service."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .off:
                            EmptyView()
                        }
                    }
                }
            }
        } header: {
            Text(String.loc("Instant Webhook Sync"))
        } footer: {
            Text(String.loc("Off by default. When enabled, a random port on 127.0.0.1 accepts POST /hook/<id>. The HMAC secret is stored only in Keychain. Cloudflare and Tailscale are optional runtime dependencies that must be installed locally."))
        }

        if webhookStore.preferences.listenerEnabled {
            webhookHookURLSection()
            webhookLastEventSection()
            webhookSendTestSection()
        }
    }

    @ViewBuilder
    private func webhookHookURLSection() -> some View {
        Section {
            if let repo = webhooks.testTargetMirror {
                let path = webhooks.hookPath(for: repo)
                HStack {
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: DesignTokens.Spacing.sm)
                    Button(String.loc("Copy")) {
                        ClipboardService.copy(path)
                    }
                }
            } else {
                Text(String.loc("Enable instant webhook sync on a repository to get a hook path."))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String.loc("Repository Hook URL"))
        }
    }

    @ViewBuilder
    private func webhookLastEventSection() -> some View {
        Section {
            Text(WebhookLastEventFormatting.displayOrEmpty(webhooks.lastEvent))
                .foregroundStyle(webhooks.lastEvent == nil ? .secondary : .primary)
        } header: {
            Text(String.loc("Last Event"))
        }
    }

    @ViewBuilder
    private func webhookSendTestSection() -> some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                Button(String.loc("Send Test")) {
                    Task { await webhooks.sendTest() }
                }
                .disabled(!webhooks.canSendTest)
            }
        }
    }

    @ViewBuilder
    private func cacheSection() -> some View {
        @Bindable var cache = cacheStore

        Section {
            Toggle(String.loc("Limit local mirror cache size"), isOn: $limitMirrorCache)
                .onChange(of: limitMirrorCache) { _, enabled in
                    cache.preferences.cacheQuotaGB = enabled ? mirrorCacheQuotaGB : nil
                    mirrorCache.refreshUsage()
                }

            if limitMirrorCache {
                Stepper(value: $mirrorCacheQuotaGB, in: 1...1000) {
                    Text(String(format: String.loc("Cache quota: %lld GB"), mirrorCacheQuotaGB))
                }
                .onChange(of: mirrorCacheQuotaGB) { _, value in
                    if limitMirrorCache {
                        cache.preferences.cacheQuotaGB = value
                    }
                }
            }
        } header: {
            Text(String.loc("Mirror Cache"))
        } footer: {
            Text(String.loc("Bare clones are stored under ~/.local/share/gitrelay/mirrors/. When over quota, GitRelay runs git gc on least-recently synced mirrors first, then deletes entire clones if needed. The next sync rebuilds deleted mirrors."))
        }

        Section {
            LabeledContent(String.loc("Local Mirrors")) {
                Text(MirrorCacheFormatting.byteCount(mirrorCache.usageBytes))
                    .foregroundStyle(.secondary)
            }

            if mirrorCache.mirrorUsages.isEmpty {
                Text(String.loc("No local mirrors."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mirrorCache.mirrorUsages) { usage in
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text(usage.name)

                        Spacer(minLength: DesignTokens.Spacing.sm)

                        Text(MirrorCacheFormatting.byteCount(usage.sizeBytes))
                            .foregroundStyle(.secondary)

                        Button(String.loc("Clean")) {
                            Task { await mirrorCache.clean(mirrorID: usage.repoID) }
                        }
                        .disabled(
                            mirrorCache.isCleaning
                                || operations.inProgressSyncIDs.contains(usage.repoID)
                        )
                    }
                }
            }

            Button(String.loc("Clean All")) {
                Task { await mirrorCache.cleanAll() }
            }
            .disabled(mirrorCache.isCleaning || mirrorCache.mirrorUsages.isEmpty)
        }
    }

    @ViewBuilder
    private func languageSection() -> some View {
        @Bindable var languageStore = languageStore

        Section {
            Picker(String.loc("Language"), selection: $languageStore.preference) {
                ForEach(AppLanguagePreference.allCases) { choice in
                    Text(choice.livePickerLabel).tag(choice)
                }
            }
            .labelsHidden()
        } header: {
            Text(String.loc("Language"))
        }
    }

    @ViewBuilder
    private func configurationSections() -> some View {
        Section {
            configurationAction(
                String.loc("Export Configuration…"),
                systemImage: "square.and.arrow.up"
            ) {
                exportConfiguration()
            }
            configurationAction(
                String.loc("Import Configuration…"),
                systemImage: "square.and.arrow.down"
            ) {
                presentImportPanel()
            }
            configurationAction(
                String.loc("Restore Defaults"),
                systemImage: "arrow.counterclockwise",
                role: .destructive
            ) {
                preferencesStore.resetToDefaults()
                securityStore.resetToDefaults()
                cacheStore.resetToDefaults()
                behaviorStore.resetToDefaults()
                appPreferences.defaultPolicyStore.resetToDefaults()
                webhooks.preferences.resetToDefaults()
                loginItem.setEnabled(false)
                syncCacheControlsFromStore()
                mirrorCache.refreshUsage()
            }
        } header: {
            Text(String.loc("Configuration"))
        }
    }

    private func configurationAction(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? DesignTokens.StatusColor.error : Color.primary)
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
            let data = try management.exportData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "gitrelay-config.json"
            panel.canCreateDirectories = true
            panel.title = String.loc("Export Configuration")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            configMessage = String.loc("Configuration exported. Tokens and private keys were not included.")
        } catch {
            configMessage = error.localizedDescription
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = String.loc("Import Configuration")
        panel.prompt = String.loc("Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingImportURL = url
        showImportModePicker = true
    }

    private func runImport(mode: ConfigImportMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        do {
            let data = try Data(contentsOf: url)
            let plan = try management.importConfiguration(from: data, mode: mode)
            if plan.skippedRepoCount > 0 {
                configMessage = String(
                    format: String.loc(
                        "Imported %lld repositories (skipped %lld existing). Repositories missing credentials are marked and will not sync until you edit them."
                    ),
                    plan.importedRepoCount,
                    plan.skippedRepoCount
                )
            } else {
                configMessage = String(
                    format: String.loc(
                        "Imported %lld repositories. Repositories missing credentials are marked and will not sync until you edit them."
                    ),
                    plan.importedRepoCount
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
                available ? String(format: String.loc("%@ detected"), tool) : String(format: String.loc("%@ not detected (you can install it manually)"), tool),
                systemImage: available ? "checkmark.circle" : "questionmark.circle"
            )
            .font(.caption)
            .foregroundStyle(available ? DesignTokens.StatusColor.success : .secondary)

            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: DesignTokens.Spacing.sm)
                Button(String.loc("Copy")) {
                    ClipboardService.copy(command)
                }
                .font(.caption)
            }
        }
    }
}
