import SwiftUI

struct OrgSubscriptionSettingsView: View {
    @Environment(AppViewModel.self) private var appVM
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

                if let next = appVM.nextOrgSubscriptionFireDate() {
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
                if appVM.orgSubscriptions.isEmpty {
                    Text(String.loc("No org or group subscriptions yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appVM.orgSubscriptions) { subscription in
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
                                    appVM.removeOrgSubscription(id: subscription.id)
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
                    Task { await appVM.triggerOrgSubscriptionPollNow() }
                }
                .disabled(appVM.orgSubscriptions.isEmpty)
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
            get: { appVM.orgSubscriptionPreferences.pollFrequency },
            set: { newValue in
                var prefs = appVM.orgSubscriptionPreferences
                prefs.pollFrequency = newValue
                appVM.updateOrgSubscriptionPreferences(prefs)
            }
        )
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { appVM.orgSubscriptionPreferences.notificationsEnabled },
            set: { newValue in
                var prefs = appVM.orgSubscriptionPreferences
                prefs.notificationsEnabled = newValue
                appVM.updateOrgSubscriptionPreferences(prefs)
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
                Text(subscription.provider.displayName)
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
    @Environment(AppViewModel.self) private var appVM
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
                    Picker(String.loc("Provider"), selection: $provider) {
                        ForEach(GitProvider.listingCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
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
                        Text(String.loc("GitRelay notifies you and opens Browse Remote prefilled so you can review before mirroring."))
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
                targetToken = appVM.orgSubscriptionStore.loadTargetToken(for: id) ?? ""
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
            lastCheckedAt: existingID.flatMap { id in appVM.orgSubscriptions.first { $0.id == id }?.lastCheckedAt }
        )
        if existingID == nil {
            appVM.addOrgSubscription(subscription)
        } else {
            appVM.updateOrgSubscription(subscription)
        }
        if !targetToken.isEmpty {
            try? appVM.saveOrgSubscriptionTargetToken(targetToken, for: subscription.id)
        }
        dismiss()
    }
}
