import SwiftUI

struct AddEditRepoSheet: View {
    let editingRepo: RepoConfig?
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss

    @State private var vm: AddEditRepoViewModel

    init(repo: RepoConfig?) {
        editingRepo = repo
        _vm = State(initialValue: AddEditRepoViewModel(editing: repo))
    }

    private var title: String { editingRepo == nil ? String(localized: "Add Repository") : String(localized: "Edit Repository") }
    private var primaryActionTitle: String { editingRepo == nil ? String(localized: "Add and Start Syncing") : String(localized: "Save") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section("Name") {
                    TextField("For example: my-project", text: $vm.name)
                    if let err = vm.nameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Source Repository") {
                    TextField("git@gitlab.com:org/repo.git", text: $vm.srcURL)
                        .font(.system(.caption, design: .monospaced))
                    if let err = vm.srcError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    AuthFieldView(
                        label: "Source",
                        remoteURL: vm.srcURL,
                        mode: $vm.srcAuthMode,
                        keyPath: $vm.srcKeyPath,
                        token: $vm.srcToken
                    )
                }

                Section {
                    ForEach(Array(vm.targets.enumerated()), id: \.element.id) { index, _ in
                        MirrorTargetCardView(
                            index: index,
                            target: binding(for: vm.targets[index].id),
                            error: vm.targetErrors[vm.targets[index].id],
                            canRemove: vm.targets.count > 1,
                            onRemove: { vm.removeTarget(id: vm.targets[index].id) }
                        )
                    }

                    Button {
                        vm.addTarget()
                    } label: {
                        Label("Add Target", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Targets")
                } footer: {
                    Text("A source repository can be mirrored to multiple targets. Choose a Git remote or filesystem archive (tar.gz, zip, or git bundle). Disabled targets are skipped during sync.")
                        .font(.caption)
                }

                Section("Sync Frequency") {
                    FrequencyPickerView(frequency: $vm.frequency)
                }

                Section("Tags") {
                    TagTokenInputView(
                        tags: $vm.tags,
                        suggestions: appVM.allKnownTags
                    )
                }

                Section("Verification Branch") {
                    TextField("main", text: $vm.defaultBranch)
                        .font(.system(.body, design: .monospaced))
                    Text("Integrity verification compares this branch's tip and tree hash on src and dst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Destructive Push Protection") {
                    Picker("Policy", selection: $vm.destructivePushPolicy) {
                        ForEach(DestructivePushPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(vm.destructivePushPolicy.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Release Mirroring") {
                    Toggle("Mirror Releases and Binary Assets", isOn: $vm.mirrorReleases)
                    Text("After syncing the git repository, incrementally copy source Release tags, titles, bodies, and attachments such as .dmg and .tar.gz files to each enabled target. A GitHub or GitLab API token is required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Allow Instant Webhook Sync", isOn: $vm.webhookEnabled)
                    if vm.webhookEnabled {
                        if let editing = editingRepo {
                            Text("Path: /hook/\(editing.webhookPathID)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)

                            let url = appVM.webhookURL(for: editing)
                            HStack {
                                Text(url)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                Spacer()
                                Button("Copy URL") { ClipboardService.copy(url) }
                                    .font(.caption)
                            }

                            if let secret = WebhookSecretStore.loadSecret(repoID: editing.id) {
                                HStack {
                                    Text("HMAC secret saved in Keychain")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Copy Secret") { ClipboardService.copy(secret) }
                                        .font(.caption)
                                }
                            }
                        } else {
                            Text("Saving generates a /hook/<repo-id> path and an HMAC secret stored in Keychain. Also enable the local listener in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Try to Register the Webhook Through the GitHub API When Saving", isOn: $vm.registerWebhookOnSave)
                        if vm.registerWebhookOnSave {
                            if let disclosure = ProviderTokenUsage.webhookRegistration(provider: .github).disclosureText {
                                Text(disclosure)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            SecureField("GitHub Token (Requires admin:repo_hook)", text: $vm.webhookRegistrationToken)
                            TokenScopeBannerView(validation: vm.webhookScopeValidation)
                            if let message = vm.webhookRegistrationMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Webhook")
                } footer: {
                    Text("Sync immediately after receiving a verified push event, independent of the frequency schedule. Enable the local listener in Settings → Webhook. Cloudflare Tunnel or Tailscale Funnel can optionally provide external access.")
                }

                Section {
                    DisclosureGroup("Advanced Options") {
                        TextField("Clone Depth (Blank = Full History)", text: $vm.depthText)
                            .font(.system(.body, design: .monospaced))
                        if let err = vm.depthError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fetch Refspecs (One per Line)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $vm.refSpecsText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 72)
                        }

                        Text("By default, all branches and tags are synced. You can limit this to main and v* tags, for example:\n+refs/heads/main:refs/heads/main\n+refs/tags/v*:refs/tags/v*")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let warning = vm.partialSyncWarning {
                            Label {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section {
                    Label {
                        Text("GitRelay performs a dry run first. Strict Protection asks for confirmation before deletions or forced updates; canceling blocks the sync and records a failure. Run Automatically preserves traditional mirror behavior.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(primaryActionTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(minHeight: 760)
    }

    private func binding(for id: UUID) -> Binding<MirrorTargetDraft> {
        Binding(
            get: { vm.targets.first(where: { $0.id == id }) ?? MirrorTargetDraft() },
            set: { newValue in
                guard let index = vm.targets.firstIndex(where: { $0.id == id }) else { return }
                vm.targets[index] = newValue
            }
        )
    }

    private func save() {
        guard vm.validate() else { return }
        let config = vm.buildRepoConfig()
        vm.saveTokensToKeychain(repoID: config.id)
        if editingRepo != nil {
            appVM.updateRepo(config)
        } else {
            appVM.addRepo(config)
            appVM.triggerSync(repoID: config.id)
        }

        if vm.webhookEnabled, vm.registerWebhookOnSave {
            let hookURL = appVM.webhookURL(for: config)
            let token = vm.webhookRegistrationToken
            Task {
                let message = await Self.registerGitHubWebhook(
                    repo: config,
                    hookURL: hookURL,
                    token: token
                )
                await MainActor.run {
                    if let message {
                        appVM.errorMessage = message
                    }
                }
            }
        }
        dismiss()
    }

    private static func registerGitHubWebhook(
        repo: RepoConfig,
        hookURL: String,
        token: String
    ) async -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return String(localized: "Automatic webhook registration was skipped because no GitHub token was provided.")
        }
        guard let path = GitRemoteRepoPath.parse(from: repo.srcURL), !path.namespace.isEmpty else {
            return String(localized: "Automatic webhook registration was skipped because owner/repo could not be parsed from the source URL.")
        }
        let client = GitHubWebhookAPIClient(token: trimmed)
        do {
            let scopes = try await client.fetchTokenScopes()
            let validation = ProviderTokenScope.validate(
                grantedScopes: scopes,
                usage: .webhookRegistration(provider: .github)
            )
            guard validation.isFullyAuthorized else {
                return String(localized: "Automatic webhook registration was skipped because the token lacks admin:repo_hook.")
            }
            let secret = try WebhookSecretStore.ensureSecret(repoID: repo.id)
            let registration = try await client.createPushHook(
                owner: path.namespace,
                repo: path.name,
                hookURL: hookURL,
                secret: secret
            )
            return String(localized: "Registered webhook #\(registration.id) on GitHub.")
        } catch {
            return String(localized: "Automatic webhook registration failed: \(error.localizedDescription)")
        }
    }
}
