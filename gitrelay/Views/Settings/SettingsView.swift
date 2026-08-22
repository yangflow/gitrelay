import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case security
    case notifications
    case schedule
    case webhook
    case cache
    case configuration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .security:
            String.loc("Security")
        case .notifications:
            String.loc("Notifications")
        case .schedule:
            String.loc("Schedule")
        case .webhook:
            String.loc("Webhook")
        case .cache:
            String.loc("Cache")
        case .configuration:
            String.loc("Configuration")
        }
    }

    var systemImage: String {
        switch self {
        case .security:
            "lock.shield"
        case .notifications:
            "bell"
        case .schedule:
            "calendar"
        case .webhook:
            "bolt.horizontal"
        case .cache:
            "internaldrive"
        case .configuration:
            "gearshape"
        }
    }
}

/// Six locked top tabs. No sidebar, no extra panes.
private struct SettingsPaneTabBar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.paneTabGap) {
                ForEach(SettingsPane.allCases) { pane in
                    tab(pane)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)

            Divider()
        }
    }

    private func tab(_ pane: SettingsPane) -> some View {
        let isSelected = pane == selection
        return Button {
            selection = pane
        } label: {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(pane.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: DesignTokens.Size.paneTabUnderline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

struct SettingsView: View {
    @Environment(NotificationPreferencesStore.self) private var preferencesStore
    @Environment(SecurityPreferencesStore.self) private var securityStore
    @Environment(CachePreferencesStore.self) private var cacheStore
    @Environment(AppBehaviorPreferencesStore.self) private var behaviorStore
    @Environment(AppViewModel.self) private var appVM
    @Environment(AppLanguageStore.self) private var languageStore

    @State private var selectedPane: SettingsPane = .security
    @State private var loginItem = LoginItemController()
    @State private var limitMirrorCache = false
    @State private var mirrorCacheQuotaGB = 50
    @State private var showImportModePicker = false
    @State private var pendingImportURL: URL?
    @State private var configMessage: String?
    @State private var accountSummaries: [ProviderAccountSummary] = []
    @State private var tokenTestOutcomes: [String: ProviderTokenTestOutcome] = [:]
    @State private var accountsUnderTest: Set<String> = []
    @State private var isPresentingAddToken = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeaderView(title: MainSidebarItem.settings.title)

            SettingsPaneTabBar(selection: paneSelection)

            detailForm
                .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loginItem.refresh()
            syncCacheControlsFromStore()
            appVM.refreshMirrorCacheUsage()
            reloadAccounts()
        }
        .sheet(isPresented: $isPresentingAddToken) {
            AddProviderTokenSheet(
                onSaved: { provider, label in
                    reloadAccounts()
                    testToken(provider: provider, accountLabel: label)
                }
            )
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
        switch selectedPane {
        case .security:
            Form { securitySections() }
        case .notifications:
            Form { notificationsSection() }
        case .schedule:
            Form { scheduleSections() }
        case .webhook:
            Form { webhookSection() }
        case .cache:
            Form { cacheSection() }
        case .configuration:
            Form { configurationSections() }
        }
    }

    @ViewBuilder
    private func securitySections() -> some View {
        @Bindable var security = securityStore
        @Bindable var behavior = behaviorStore

        accountsSection()

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
                    String(
                        localized: "Open at Login needs approval in System Settings → General → Login Items."
                    )
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
        } footer: {
            Text(
                String(
                    localized: "When enabled, closing the main window leaves GitRelay in the menu bar (Dock icon may hide). Turn off to quit when the last window closes."
                )
            )
        }

        Section {
            Toggle(
                String.loc("Require Touch ID or password for sensitive actions"),
                isOn: $security.preferences.requireBiometricForSensitive
            )
        } header: {
            Text(String.loc("Security"))
        } footer: {
            Text(String.loc("When enabled, viewing tokens in plaintext, deleting repositories, and changing a mirror target to a different host require authentication. Canceling or failing authentication aborts the action."))
        }
    }

    // MARK: - Accounts (issue #104)

    private var visibleAccounts: [ProviderAccountSummary] {
        accountSummaries
    }

    @ViewBuilder
    private func accountsSection() -> some View {
        Section {
            if visibleAccounts.isEmpty {
                Text(String.loc("No account is connected yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleAccounts) { summary in
                    ProviderAccountRowView(
                        summary: summary,
                        outcome: tokenTestOutcomes[summary.id],
                        isTesting: accountsUnderTest.contains(summary.id),
                        onTest: {
                            testToken(provider: summary.provider, accountLabel: summary.label)
                        }
                    )
                }
            }

            Button {
                isPresentingAddToken = true
            } label: {
                Label(String.loc("Add Token"), systemImage: "plus")
            }
        } header: {
            Text(String.loc("Accounts"))
        } footer: {
            Text(String.loc("Tokens are stored in the Keychain and are never written to a log or to exported configuration. Test asks the provider whether a saved token still works."))
        }
    }

    private func reloadAccounts() {
        accountSummaries = ProviderAccountSummary.listed(
            ProviderAccountSummary.summaries(
                recordsByProvider: ProviderAccountStore.allAccounts(),
                hasToken: { provider, label in
                    ProviderTokenStore.load(provider: provider, accountLabel: label) != nil
                }
            )
        )
    }

    private func testToken(provider: GitProvider, accountLabel: String) {
        let id = ProviderAccount.id(provider: provider, label: accountLabel)
        guard !accountsUnderTest.contains(id) else { return }
        accountsUnderTest.insert(id)
        tokenTestOutcomes[id] = nil

        Task {
            let outcome = await ProviderTokenTester.run(
                provider: provider,
                accountLabel: accountLabel,
                host: ProviderAccountStore.host(for: provider, label: accountLabel)
            )
            accountsUnderTest.remove(id)
            tokenTestOutcomes[id] = outcome
            reloadAccounts()
        }
    }

    private var paneSelection: Binding<SettingsPane> {
        Binding(
            get: { selectedPane },
            set: { selectedPane = $0 }
        )
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
                Text(String.loc("Consecutive failure threshold: \(store.preferences.consecutiveFailureThreshold)"))
            }
            .disabled(!store.preferences.notificationsEnabled)

            Picker(String.loc("Notification Level"), selection: $store.preferences.interruptionLevel) {
                ForEach(NotificationInterruptionPreference.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .disabled(!store.preferences.notificationsEnabled)

            Text(store.preferences.interruptionLevel.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String.loc("Failure Notifications"))
        } footer: {
            Text(String.loc("Notify only on the first failure (optional), or when consecutive failures reach the threshold and its multiples, to avoid alerts from brief network interruptions. Notifications are deferred while Focus is on and combined into a summary afterward."))
        }
    }

    @ViewBuilder
    private func scheduleSections() -> some View {
        @Bindable var store = preferencesStore

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
                    String(
                        localized: "Max concurrent syncs: \(store.preferences.maxConcurrentSyncs)"
                    )
                )
            }
        } header: {
            Text(String.loc("Sync Concurrency"))
        } footer: {
            Text(String.loc("Manual, webhook, and scheduled syncs share this limit. Extra requests wait in a queue (Queued) until a slot frees. Quitting the app discards the queue."))
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

            if let reason = appVM.scheduledSyncPauseReason {
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
        @Bindable var webhookStore = appVM.webhookPreferences

        Section {
            Toggle(String.loc("Enable local webhook listener"), isOn: $webhookStore.preferences.listenerEnabled)

            if webhookStore.preferences.listenerEnabled {
                if let port = appVM.webhookListenPort {
                    LabeledContent(String.loc("Listening Address")) {
                        Text(String.loc("127.0.0.1:\(port)"))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    Text(appVM.isWebhookListenerRunning ? String.loc("Binding port…") : String.loc("Listener Not Running"))
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
            if let repo = appVM.webhookTestTargetRepo {
                let path = appVM.webhookHookPath(for: repo)
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
            Text(WebhookLastEventFormatting.displayOrEmpty(appVM.webhookLastEvent))
                .foregroundStyle(appVM.webhookLastEvent == nil ? .secondary : .primary)
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
                    Task { await appVM.sendWebhookTest() }
                }
                .disabled(!appVM.canSendWebhookTest)
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
                    appVM.refreshMirrorCacheUsage()
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
                Text(MirrorCacheFormatting.byteCount(appVM.mirrorCacheUsageBytes))
                    .foregroundStyle(.secondary)
            }

            if appVM.mirrorCacheRepoUsages.isEmpty {
                Text(String.loc("No local mirrors."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appVM.mirrorCacheRepoUsages) { usage in
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text(usage.name)

                        Spacer(minLength: DesignTokens.Spacing.sm)

                        Text(MirrorCacheFormatting.byteCount(usage.sizeBytes))
                            .foregroundStyle(.secondary)

                        Button(String.loc("Clean")) {
                            Task { await appVM.cleanMirrorCache(for: usage.repoID) }
                        }
                        .disabled(
                            appVM.isCleaningMirrorCache
                                || appVM.inProgressSyncIDs.contains(usage.repoID)
                        )
                    }
                }
            }

            Button(String.loc("Clean All")) {
                Task { await appVM.cleanMirrorCacheNow() }
            }
            .disabled(appVM.isCleaningMirrorCache || appVM.mirrorCacheRepoUsages.isEmpty)
        }
    }

    @ViewBuilder
    private func configurationSections() -> some View {
        @Bindable var languageStore = languageStore

        Section {
            Picker(String.loc("Language"), selection: $languageStore.preference) {
                ForEach(AppLanguagePreference.allCases) { choice in
                    Text(choice.pickerLabel).tag(choice)
                }
            }

            if languageStore.showsLaunchCatalogNote {
                Text(String.loc("Some text updates the next time you open GitRelay."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String.loc("Language"))
        }

        Section {
            Button(String.loc("Export Configuration…")) {
                exportConfiguration()
            }
            Button(String.loc("Import Configuration…")) {
                presentImportPanel()
            }
        } header: {
            Text(String.loc("Configuration"))
        } footer: {
            Text(String.loc("Export repository pairs, targets, tags, frequency, shallow/ref filters, LFS, org subscriptions, and account labels. Tokens and private keys are never written to the file. After import, repositories missing credentials are marked and stay unscheduled until you fill them in."))
        }

        Section {
            Button(String.loc("Restore Defaults")) {
                preferencesStore.resetToDefaults()
                securityStore.resetToDefaults()
                cacheStore.resetToDefaults()
                behaviorStore.resetToDefaults()
                appVM.webhookPreferences.resetToDefaults()
                loginItem.setEnabled(false)
                syncCacheControlsFromStore()
                appVM.refreshMirrorCacheUsage()
            }
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
                available ? String.loc("\(tool) detected") : String.loc("\(tool) not detected (you can install it manually)"),
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
