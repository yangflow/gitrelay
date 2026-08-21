import SwiftUI

struct AddEditRepoSheet: View {
    let editingRepo: RepoConfig?
    let focusAuth: Bool

    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss

    @State private var vm: AddEditRepoViewModel
    @State private var didScrollToAuth = false

    init(repo: RepoConfig?, prefill: RepoSourceDropPrefill? = nil, focusAuth: Bool = false) {
        editingRepo = repo
        self.focusAuth = focusAuth
        _vm = State(initialValue: AddEditRepoViewModel(editing: repo, prefill: prefill))
    }

    private var title: String {
        if editingRepo != nil {
            return String(localized: "Edit Repository")
        }
        return vm.showsMoreOptions
            ? String(localized: "More Options")
            : String(localized: "Add Repository")
    }

    private var primaryActionTitle: String {
        editingRepo == nil ? String(localized: "Add and Start Syncing") : String(localized: "Save")
    }

    /// Add flow step 1: required fields only.
    private var showsBasicsOnly: Bool {
        editingRepo == nil && !vm.showsMoreOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .gitRelaySheetHeaderPadding()

            Divider()

            ScrollViewReader { proxy in
                Form {
                    if focusAuth, editingRepo != nil {
                        Section {
                            Text(String(localized: "Update the token or SSH key for this repository, then save."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text(String(localized: "Authentication"))
                        }
                    }

                    if showsBasicsOnly {
                        basicsSections(primaryTargetOnly: true)
                    } else if editingRepo != nil {
                        basicsSections(primaryTargetOnly: false)
                        moreOptionsSections(includeExtraTargets: false)
                    } else {
                        // Add step 2: only the optional fields (including extra targets).
                        moreOptionsSections(includeExtraTargets: true)
                    }
                }
                .formStyle(.grouped)
                .onAppear {
                    scrollToAuthIfNeeded(proxy: proxy)
                }
            }

            Divider()

            footer
        }
        .frame(width: 520)
        .frame(minHeight: showsBasicsOnly ? 520 : 760)
        .gitRelayChrome(.sheet)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if editingRepo == nil, vm.showsMoreOptions {
                Button(String(localized: "Back")) {
                    vm.backToBasics()
                }
            }
            Spacer()
            Button(String(localized: "Cancel")) { dismiss() }
                .keyboardShortcut(.escape)
            if showsBasicsOnly {
                Button(String(localized: "More Options")) {
                    _ = vm.openMoreOptions()
                }
            }
            Button(primaryActionTitle, action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .gitRelaySheetFooterPadding()
    }

    @ViewBuilder
    private func basicsSections(primaryTargetOnly: Bool) -> some View {
        Section {
            TextField("For example: my-project", text: $vm.name)
            if let err = vm.nameError {
                Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
            }
        } header: {
            Text(String(localized: "Name"))
        }

        Section {
            TextField("git@gitlab.com:org/repo.git", text: $vm.srcURL)
                .font(.system(.caption, design: .monospaced))
            if let err = vm.srcError {
                Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
            }
            AuthFieldView(
                label: String(localized: "Source"),
                remoteURL: vm.srcURL,
                mode: $vm.srcAuthMode,
                keyPath: $vm.srcKeyPath,
                token: $vm.srcToken
            )
            .id(AddEditRepoScrollTarget.sourceAuth)
        } header: {
            Text(String(localized: "Source Repository"))
        }

        Section {
            ForEach(Array(vm.targets.enumerated()), id: \.element.id) { index, _ in
                if !primaryTargetOnly || index == 0 {
                    MirrorTargetCardView(
                        index: index,
                        target: binding(for: vm.targets[index].id),
                        error: vm.targetErrors[vm.targets[index].id],
                        canRemove: !primaryTargetOnly && vm.targets.count > 1,
                        onRemove: { vm.removeTarget(id: vm.targets[index].id) }
                    )
                }
            }

            if !primaryTargetOnly {
                Button {
                    vm.addTarget()
                } label: {
                    Label(String(localized: "Add Target"), systemImage: "plus.circle")
                }
            }
        } header: {
            Text(String(localized: "Targets"))
        } footer: {
            if primaryTargetOnly {
                Text(String(localized: "Add more targets under More Options."))
                    .font(.caption)
            } else {
                Text(String(localized: "A source repository can be mirrored to multiple targets. Choose a Git remote or filesystem archive (tar.gz, zip, or git bundle). Disabled targets are skipped during sync."))
                    .font(.caption)
            }
        }

        Section {
            FrequencyPickerView(frequency: $vm.frequency)
        } header: {
            Text(String(localized: "Sync Frequency"))
        }
    }

    @ViewBuilder
    private func moreOptionsSections(includeExtraTargets: Bool) -> some View {
        if includeExtraTargets {
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
                    Label(String(localized: "Add Target"), systemImage: "plus.circle")
                }
            } header: {
                Text(String(localized: "Targets"))
            } footer: {
                Text(String(localized: "A source repository can be mirrored to multiple targets. Choose a Git remote or filesystem archive (tar.gz, zip, or git bundle). Disabled targets are skipped during sync."))
                    .font(.caption)
            }
        }

        Section {
            TagTokenInputView(
                tags: $vm.tags,
                suggestions: appVM.allKnownTags
            )
        } header: {
            Text(String(localized: "Tags"))
        }

        Section {
            TextField("main", text: $vm.defaultBranch)
                .font(.system(.body, design: .monospaced))
            Text(String(localized: "Integrity verification compares this branch's tip and tree hash on src and dst."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Verification Branch"))
        }

        Section {
            Picker(String(localized: "Policy"), selection: $vm.destructivePushPolicy) {
                ForEach(DestructivePushPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.segmented)

            Text(vm.destructivePushPolicy.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Destructive Push Protection"))
        }

        Section {
            Toggle(String(localized: "Mirror Releases and Binary Assets"), isOn: $vm.mirrorReleases)
            Text(String(localized: "After syncing the git repository, incrementally copy source Release tags, titles, bodies, and attachments such as .dmg and .tar.gz files to each enabled target. A GitHub or GitLab API token is required."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Release Mirroring"))
        }

        Section {
            Picker(String(localized: "Git LFS"), selection: $vm.lfsMirrorMode) {
                ForEach(LFSMirrorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(vm.lfsMirrorMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if vm.lfsMirrorMode == .auto {
                Text(LFSMirrorMessages.installHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "Git LFS Objects"))
        }

        Section {
            Toggle(String(localized: "Allow Instant Webhook Sync"), isOn: $vm.webhookEnabled)
            if vm.webhookEnabled {
                if let editing = editingRepo {
                    Text(String(localized: "Path: /hook/\(editing.webhookPathID)"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    let url = appVM.webhookURL(for: editing)
                    HStack {
                        Text(url)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                        Button(String(localized: "Copy URL")) { ClipboardService.copy(url) }
                            .font(.caption)
                    }

                    if let secret = WebhookSecretStore.loadSecret(repoID: editing.id) {
                        HStack {
                            Text(String(localized: "HMAC secret saved in Keychain"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(String(localized: "Copy Secret")) { ClipboardService.copy(secret) }
                                .font(.caption)
                        }
                    }
                } else {
                    Text(String(localized: "Saving generates a /hook/<repo-id> path and an HMAC secret stored in Keychain. Also enable the local listener in Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(String(localized: "Try to Register the Webhook Through the GitHub API When Saving"), isOn: $vm.registerWebhookOnSave)
                if vm.registerWebhookOnSave {
                    if let disclosure = ProviderTokenUsage.webhookRegistration(provider: .github).disclosureText {
                        Text(disclosure)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.warning)
                    }
                    GatedSecureTokenField(
                        placeholder: "GitHub Token (Requires admin:repo_hook)",
                        text: $vm.webhookRegistrationToken
                    )
                    TokenScopeBannerView(validation: vm.webhookScopeValidation)
                    if let message = vm.webhookRegistrationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(String(localized: "Webhook"))
        } footer: {
            Text(String(localized: "Sync immediately after receiving a verified push event, independent of the frequency schedule. Enable the local listener in Settings → Webhook. Cloudflare Tunnel or Tailscale Funnel can optionally provide external access."))
        }

        Section {
            DisclosureGroup(String(localized: "Advanced Options")) {
                TextField(String(localized: "Clone Depth (Blank = Full History)"), text: $vm.depthText)
                    .font(.system(.body, design: .monospaced))
                if let err = vm.depthError {
                    Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                    Text(String(localized: "Fetch Refspecs (One per Line)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $vm.refSpecsText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 72)
                }

                Text(String(localized: "By default, all branches and tags are synced. You can limit this to main and v* tags, for example:\n+refs/heads/main:refs/heads/main\n+refs/tags/v*:refs/tags/v*"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = vm.partialSyncWarning {
                    Label {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.warning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DesignTokens.StatusColor.warning)
                    }
                }
            }
        }

        Section {
            Label {
                Text(String(localized: "GitRelay performs a dry run first. Strict Protection asks for confirmation before deletions or forced updates; canceling blocks the sync and records a failure. Run Automatically preserves traditional mirror behavior."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
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
        guard vm.validate() else {
            if editingRepo == nil {
                // Keep the user on step 1 when required fields fail.
                if vm.nameError != nil || vm.srcError != nil || !vm.targetErrors.isEmpty {
                    vm.showsMoreOptions = false
                }
            }
            return
        }
        Task { await saveAfterAuthorization() }
    }

    private func saveAfterAuthorization() async {
        if let editing = editingRepo {
            for change in vm.gitRemoteTargetHostChanges(comparedTo: editing) {
                let action = SensitiveAction.changeTargetHost(
                    originalURL: change.originalURL,
                    newURL: change.newURL
                )
                guard await appVM.authorizeSensitiveAction(action) else { return }
            }
        }
        performSave()
    }

    private func performSave() {
        let config = vm.buildRepoConfig()
        vm.saveTokensToKeychain(repoID: config.id)
        vm.rememberLastUsedAuthMode()
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

    private func scrollToAuthIfNeeded(proxy: ScrollViewProxy) {
        guard focusAuth, editingRepo != nil, !didScrollToAuth else { return }
        didScrollToAuth = true
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(AddEditRepoScrollTarget.sourceAuth, anchor: .top)
            }
        }
    }
}

private enum AddEditRepoScrollTarget {
    static let sourceAuth = "add-edit-source-auth"
}
