import SwiftUI

struct OrgSubscriptionSettingsView: View {
    @Environment(AppViewModel.self) private var appVM
    @State private var editingSubscription: OrgSubscription?
    @State private var isAddingSubscription = false

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Poll Frequency"), selection: pollFrequencyBinding) {
                    ForEach(OrgSubscriptionPollFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Toggle(
                    String(localized: "Notify when new repositories are discovered"),
                    isOn: notificationsEnabledBinding
                )

                if let next = appVM.nextOrgSubscriptionFireDate() {
                    LabeledContent(String(localized: "Next Poll")) {
                        Text(next, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "Org / Group Discovery"))
            } footer: {
                Text(String(localized: "Periodically compare subscribed GitHub organizations or GitLab groups against locally mirrored repositories. When new repos appear, GitRelay can notify you or auto-add them using a preset template."))
            }

            Section {
                if appVM.orgSubscriptions.isEmpty {
                    Text(String(localized: "No org or group subscriptions yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appVM.orgSubscriptions) { subscription in
                        OrgSubscriptionRow(subscription: subscription)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingSubscription = subscription
                            }
                            .contextMenu {
                                Button(String(localized: "Edit")) {
                                    editingSubscription = subscription
                                }
                                Button(String(localized: "Remove"), role: .destructive) {
                                    appVM.removeOrgSubscription(id: subscription.id)
                                }
                            }
                    }
                }

                Button(String(localized: "Subscribe to Org / Group")) {
                    isAddingSubscription = true
                }
            } header: {
                Text(String(localized: "Subscriptions"))
            }

            Section {
                Button(String(localized: "Poll Subscriptions Now")) {
                    Task { await appVM.triggerOrgSubscriptionPollNow() }
                }
                .disabled(appVM.orgSubscriptions.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 320)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(subscription.organizationName)
                .font(.headline)
            HStack(spacing: 8) {
                Text(subscription.provider.displayName)
                Text("·")
                Text(subscription.accountLabel)
                if subscription.autoAddEnabled {
                    Text("·")
                    Text(String(localized: "Auto-add"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let checked = subscription.lastCheckedAt {
                HStack(spacing: 4) {
                    Text(String(localized: "Last checked"))
                    Text(checked, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
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
                 ? String(localized: "Subscribe to Org / Group")
                 : String(localized: "Edit Subscription"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            Divider()

            Form {
                Section {
                    Picker(String(localized: "Provider"), selection: $provider) {
                        ForEach(GitProvider.listingCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) { _, _ in refreshAccounts() }

                    Picker(String(localized: "Account"), selection: $accountLabel) {
                        ForEach(accountLabels, id: \.self) { label in
                            Text(label).tag(label)
                        }
                    }

                    TextField(
                        provider == .github
                            ? String(localized: "Organization name (for example, anthropic)")
                            : String(localized: "Group path (for example, gitlab-org/charts)"),
                        text: $organizationName
                    )
                    .textFieldStyle(.roundedBorder)
                } header: {
                    Text(String(localized: "Source"))
                }

                Section {
                    Toggle(String(localized: "Auto-add using template"), isOn: $autoAddEnabled)

                    if autoAddEnabled {
                        Text(String(localized: "New repositories are mirrored immediately using the template below. Notifications are skipped when auto-add succeeds."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(String(localized: "Mirror Template"))
                            .font(.headline)
                            .padding(.top, 4)

                        Picker(String(localized: "Source Auth"), selection: $template.sourceAuthMode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        Picker(String(localized: "Target Auth"), selection: $template.targetAuthMode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        TextField(String(localized: "Target URL template (must include {name})"), text: $template.targetURLTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .disabled(template.targetAutoCreate)

                        Toggle(String(localized: "Auto-create target on Gitea"), isOn: $template.targetAutoCreate)

                        Picker(String(localized: "Sync Frequency"), selection: $template.frequency) {
                            ForEach(SyncFrequency.allCases) { f in
                                Text(f.displayName).tag(f)
                            }
                        }

                        TextField(String(localized: "Name prefix (optional)"), text: $template.namePrefix)
                            .textFieldStyle(.roundedBorder)

                        if template.targetAuthMode == .httpsToken || template.sourceAuthMode == .httpsToken {
                            GatedSecureTokenField(
                                placeholder: "Target HTTPS token (optional)",
                                text: $targetToken
                            )
                        }
                    } else {
                        Text(String(localized: "GitRelay notifies you and opens a prefilled browse sheet so you can review before mirroring."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "When New Repos Appear"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                Spacer()
                Button(existingID == nil ? String(localized: "Subscribe") : String(localized: "Save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 520, height: autoAddEnabled ? 620 : 420)
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
