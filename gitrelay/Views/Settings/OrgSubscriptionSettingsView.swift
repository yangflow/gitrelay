import SwiftUI

struct OrgSubscriptionSettingsView: View {
    @Environment(OrgDiscoveryController.self) private var orgDiscovery
    @State private var editingSubscription: OrgSubscription?
    @State private var isAddingSubscription = false

    var body: some View {
        Form {
            Section {
                Picker(String.loc("Poll Frequency"), selection: pollFrequencyBinding) {
                    ForEach(OrgSubscriptionPollFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Toggle(
                    String.loc("Notify when new repositories are discovered"),
                    isOn: notificationsEnabledBinding
                )

                if let next = orgDiscovery.nextFireDate() {
                    LabeledContent(String.loc("Next Poll")) {
                        Text(next, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String.loc("Org / Group Discovery"))
            } footer: {
                Text(String.loc("Periodically compare subscribed GitHub organizations or GitLab groups against locally mirrored repositories. When new repos appear, GitRelay can notify you or auto-add them using a preset template."))
            }

            Section {
                if orgDiscovery.subscriptions.isEmpty {
                    Text(String.loc("No org or group subscriptions yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orgDiscovery.subscriptions) { subscription in
                        OrgSubscriptionRow(subscription: subscription)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingSubscription = subscription
                            }
                            .contextMenu {
                                Button(String.loc("Edit")) {
                                    editingSubscription = subscription
                                }
                                Button(String.loc("Remove"), role: .destructive) {
                                    orgDiscovery.remove(id: subscription.id)
                                }
                            }
                    }
                }

                Button(String.loc("Subscribe to Org / Group")) {
                    isAddingSubscription = true
                }
            } header: {
                Text(String.loc("Subscriptions"))
            }

            Section {
                Button(String.loc("Poll Subscriptions Now")) {
                    Task { await orgDiscovery.pollNow() }
                }
                .disabled(orgDiscovery.subscriptions.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: DesignTokens.Layout.settingsMinWidth, minHeight: DesignTokens.Layout.orgSubscriptionSettingsMinHeight)
        .gitRelayChrome(.sheet)
        .sheet(item: $editingSubscription) { subscription in
            OrgSubscriptionEditorSheet(subscription: subscription)
        }
        .sheet(isPresented: $isAddingSubscription) {
            OrgSubscriptionEditorSheet(subscription: nil)
        }
    }

    private var pollFrequencyBinding: Binding<OrgSubscriptionPollFrequency> {
        Binding(
            get: { orgDiscovery.subscriptionPreferences.pollFrequency },
            set: { newValue in
                var prefs = orgDiscovery.subscriptionPreferences
                prefs.pollFrequency = newValue
                orgDiscovery.updatePreferences(prefs)
            }
        )
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { orgDiscovery.subscriptionPreferences.notificationsEnabled },
            set: { newValue in
                var prefs = orgDiscovery.subscriptionPreferences
                prefs.notificationsEnabled = newValue
                orgDiscovery.updatePreferences(prefs)
            }
        )
    }
}

private struct OrgSubscriptionRow: View {
    let subscription: OrgSubscription

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(subscription.organizationName)
                .font(.headline)
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProviderBrandLabel(
                    provider: subscription.provider,
                    iconSize: 13
                )
                Text("·")
                Text(subscription.accountLabel)
                if subscription.autoAddEnabled {
                    Text("·")
                    Text(String.loc("Auto-add"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let checked = subscription.lastCheckedAt {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(String.loc("Last checked"))
                    Text(checked, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxxs)
    }
}

struct OrgSubscriptionEditorSheet: View {
    @Environment(OrgDiscoveryController.self) private var orgDiscovery
    @Environment(\.dismiss) private var dismiss

    @State private var provider: GitProvider = .github
    @State private var accountLabel: String = ProviderAccount.defaultLabel
    @State private var organizationName: String = ""
    @State private var autoAddEnabled: Bool = false
    @State private var template: OrgSubscriptionTemplate = .default
    @State private var targetToken: String = ""
    @State private var accountLabels: [String] = []

    private let existingID: UUID?

    init(subscription: OrgSubscription?) {
        existingID = subscription?.id
        if let subscription {
            _provider = State(initialValue: subscription.provider)
            _accountLabel = State(initialValue: subscription.accountLabel)
            _organizationName = State(initialValue: subscription.organizationName)
            _autoAddEnabled = State(initialValue: subscription.autoAddEnabled)
            _template = State(initialValue: subscription.template)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(existingID == nil
                 ? String.loc("Subscribe to Org / Group")
                 : String.loc("Edit Subscription"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.settingsForm)

            Divider()

            Form {
                Section {
                    ProviderSegmentedControl(
                        selection: $provider,
                        providers: GitProvider.listingCases
                    )
                    .accessibilityLabel(String.loc("Provider"))
                    .onChange(of: provider) { _, _ in refreshAccounts() }

                    Picker(String.loc("Account"), selection: $accountLabel) {
                        ForEach(accountLabels, id: \.self) { label in
                            Text(label).tag(label)
                        }
                    }

                    TextField(
                        provider == .github
                            ? String.loc("Organization name (for example, anthropic)")
                            : String.loc("Group path (for example, gitlab-org/charts)"),
                        text: $organizationName
                    )
                    .textFieldStyle(.roundedBorder)
                } header: {
                    Text(String.loc("Source"))
                }

                Section {
                    Toggle(String.loc("Auto-add using template"), isOn: $autoAddEnabled)

                    if autoAddEnabled {
                        Text(String.loc("New repositories are mirrored immediately using the template below. Notifications are skipped when auto-add succeeds."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(String.loc("Mirror Template"))
                            .font(.headline)
                            .padding(.top, DesignTokens.Spacing.xxs)

                        Picker(String.loc("Source Auth"), selection: $template.sourceAuthMode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        Picker(String.loc("Target Auth"), selection: $template.targetAuthMode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        TextField(String.loc("Target URL template (must include {name})"), text: $template.targetURLTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .disabled(template.targetAutoCreate)

                        Toggle(String.loc("Auto-create target on Gitea"), isOn: $template.targetAutoCreate)

                        Picker(String.loc("Sync Frequency"), selection: $template.frequency) {
                            ForEach(SyncFrequency.allCases) { f in
                                Text(f.displayName).tag(f)
                            }
                        }

                        TextField(String.loc("Name prefix (optional)"), text: $template.namePrefix)
                            .textFieldStyle(.roundedBorder)

                        if template.targetAuthMode == .httpsToken || template.sourceAuthMode == .httpsToken {
                            GatedSecureTokenField(
                                placeholder: "Target HTTPS token (optional)",
                                text: $targetToken
                            )
                        }
                    } else {
                        Text(String.loc("GitRelay notifies you and opens Add Mirror with the service and organization preselected."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String.loc("When New Repos Appear"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button(String.loc("Cancel")) { dismiss() }
                Spacer()
                Button(existingID == nil ? String.loc("Subscribe") : String.loc("Save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(DesignTokens.Spacing.settingsForm)
        }
        .frame(width: 520, height: autoAddEnabled ? 620 : 420)
        .gitRelayChrome(.sheet)
        .onAppear {
            refreshAccounts()
            if let id = existingID {
                targetToken = orgDiscovery.store.loadTargetToken(for: id) ?? ""
            }
        }
    }

    private var canSave: Bool {
        !organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!autoAddEnabled || OrgSubscriptionTemplateApplier.isValidTemplate(template))
    }

    private func refreshAccounts() {
        accountLabels = ProviderAccountStore.accountLabels(for: provider)
        if !accountLabels.contains(accountLabel) {
            accountLabel = ProviderAccountStore.selectedLabel(for: provider)
        }
    }

    private func save() {
        let subscription = OrgSubscription(
            id: existingID ?? UUID(),
            provider: provider,
            accountLabel: accountLabel,
            organizationName: organizationName,
            autoAddEnabled: autoAddEnabled,
            template: template,
            lastCheckedAt: existingID.flatMap { id in
                orgDiscovery.subscriptions.first { $0.id == id }?.lastCheckedAt
            }
        )
        if existingID == nil {
            orgDiscovery.add(subscription)
        } else {
            orgDiscovery.update(subscription)
        }
        if !targetToken.isEmpty {
            try? orgDiscovery.saveTargetToken(targetToken, subscriptionID: subscription.id)
        }
        dismiss()
    }
}
