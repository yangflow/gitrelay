import AppKit
import SwiftUI

struct AddEditRepoSheet: View {
    let editingRepo: RepoConfig?
    let focusAuth: Bool

    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss

    @State private var vm: AddEditRepoViewModel
    @State private var preflight: AddRepoPreflightViewModel
    @State private var didScrollToAuth = false

    init(repo: RepoConfig?, prefill: RepoSourceDropPrefill? = nil, focusAuth: Bool = false) {
        editingRepo = repo
        self.focusAuth = focusAuth
        _vm = State(initialValue: AddEditRepoViewModel(editing: repo, prefill: prefill))
        _preflight = State(initialValue: AddRepoPreflightViewModel())
    }

    private var title: String {
        if editingRepo != nil {
            return vm.showsMoreOptions
                ? String.loc("More Options")
                : String.loc("Edit Repository")
        }
        return vm.showsMoreOptions
            ? String.loc("More Options")
            : String.loc("Add Repository")
    }

    private var primaryActionTitle: String {
        guard editingRepo == nil else { return String.loc("Save") }
        if preflight.primaryAction == .createDestination {
            return AddPreflightCopy.createAndStartSyncTitle
        }
        return String.loc("Add and Start Syncing")
    }

    /// Preflight only runs while adding: an existing pair has already been probed
    /// by the sync engine itself.
    private var runsPreflight: Bool {
        editingRepo == nil
    }

    /// A pair GitRelay already mirrors replaces 更多选项 with open / add anyway.
    /// Only on the basics step: the more-options step must keep its way back.
    private var showsDuplicatePairChoice: Bool {
        runsPreflight && showsBasicsOnly && preflight.offersOpenExistingPair
    }

    private var preflightInput: AddPreflightInput {
        AddPreflightInput(
            sourceURL: vm.srcURL,
            sourceCredentials: RemoteProbeCredentials(
                mode: vm.srcAuthMode,
                sshKeyPath: vm.srcKeyPath,
                token: vm.srcToken
            ),
            destinationURL: vm.primaryTargetLocation,
            destinationCredentials: primaryTargetCredentials,
            destinationIsFilesystem: vm.primaryTargetUsesFilesystemPath
        )
    }

    private var primaryTargetCredentials: RemoteProbeCredentials {
        guard let target = vm.targets.first else { return RemoteProbeCredentials() }
        return RemoteProbeCredentials(
            mode: target.authMode,
            sshKeyPath: target.keyPath,
            token: target.token
        )
    }

    /// Basics step: quiet two stacked URL fields (source + target).
    private var showsBasicsOnly: Bool {
        !vm.showsMoreOptions
    }

    private var primaryTargetID: UUID? {
        vm.targets.first?.id
    }

    private var nameFieldBinding: Binding<String> {
        Binding(
            get: { vm.name },
            set: { vm.updateName($0) }
        )
    }

    private var primaryTargetLocationBinding: Binding<String> {
        Binding(
            get: { vm.primaryTargetLocation },
            set: { vm.primaryTargetLocation = $0 }
        )
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
                Group {
                    if showsBasicsOnly {
                        ScrollView {
                            basicsContent
                                .padding(DesignTokens.Spacing.sheetContent)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    } else {
                        Form {
                            moreOptionsSections()
                        }
                        .formStyle(.grouped)
                    }
                }
                .onAppear {
                    if focusAuth, editingRepo != nil {
                        vm.openMoreOptions()
                    }
                    scrollToAuthIfNeeded(proxy: proxy)
                }
            }

            Divider()

            footer
        }
        .onAppear { refreshPreflight() }
        .onChange(of: preflightInput) { _, _ in refreshPreflight() }
        .onChange(of: appVM.repos.map(\.id)) { _, _ in refreshPreflight() }
        .onDisappear { preflight.cancel() }
        .frame(
            minWidth: DesignTokens.Layout.addEditRepoSheetMinWidth,
            minHeight: DesignTokens.Layout.addEditRepoSheetMinHeight
        )
        .gitRelayChrome(.sheet)
        .background(ResizableSheetWindowConfigurator(
            minSize: NSSize(
                width: DesignTokens.Layout.addEditRepoSheetMinWidth,
                height: DesignTokens.Layout.addEditRepoSheetMinHeight
            )
        ))
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button(String.loc("Cancel")) { dismiss() }
                .keyboardShortcut(.escape)

            if showsDuplicatePairChoice {
                Spacer()

                Button(AddPreflightCopy.openExistingTitle) { openExistingPair() }

                Button(AddPreflightCopy.addAnywayTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            } else {
                if showsBasicsOnly {
                    Button(String.loc("More Options")) {
                        vm.openMoreOptions()
                    }
                } else {
                    Button(String.loc("Back")) {
                        vm.backToBasics()
                    }
                }

                Spacer()

                Button(primaryActionTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(preflight.isCreatingDestination)
            }
        }
        .gitRelaySheetFooterPadding()
    }

    /// Locked basics: two stacked fields (Source URL + Target URL), lots of air.
    @ViewBuilder
    private var basicsContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
            if focusAuth, editingRepo != nil {
                Text(String.loc("Update the token or SSH key for this repository, then save."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(String.loc("Source"))
                    .font(.headline)

                TextField("git@gitlab.com:org/repo.git", text: $vm.srcURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                if let caption = vm.basicsInferenceCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = vm.srcError {
                    Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
                }
                if let err = vm.nameError {
                    Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(String.loc("Target"))
                    .font(.headline)

                TextField(
                    vm.primaryTargetUsesFilesystemPath
                        ? "/Volumes/Backup/git-archives"
                        : "git@github.com:user/repo.git",
                    text: primaryTargetLocationBinding
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                if let id = primaryTargetID, let err = vm.targetErrors[id] {
                    Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
                }

                if runsPreflight, let caption = preflight.caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private func moreOptionsSections() -> some View {
        Section {
            TextField("For example: my-project", text: nameFieldBinding)
            if let err = vm.nameError {
                Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
            }
        } header: {
            Text(String.loc("Name"))
        }

        Section {
            AuthFieldView(
                label: String.loc("Source"),
                remoteURL: vm.srcURL,
                mode: $vm.srcAuthMode,
                keyPath: $vm.srcKeyPath,
                token: $vm.srcToken,
                pickerTitle: String.loc("Authentication Method")
            )
            .id(AddEditRepoScrollTarget.sourceAuth)
        } header: {
            Text(String.loc("Source Authentication"))
        }

        Section {
            ForEach(Array(vm.targets.enumerated()), id: \.element.id) { index, _ in
                MirrorTargetFieldsView(
                    index: index,
                    target: binding(for: vm.targets[index].id),
                    error: vm.targetErrors[vm.targets[index].id],
                    canRemove: vm.targets.count > 1,
                    onRemove: { vm.removeTarget(id: vm.targets[index].id) },
                    showsHeader: true,
                    urlFieldTitle: String.loc("Target URL"),
                    authPickerTitle: String.loc("Authentication Method")
                )
            }

            Button {
                vm.addTarget()
            } label: {
                Label(String.loc("Add Target"), systemImage: "plus.circle")
            }
        } header: {
            Text(String.loc("Targets"))
        } footer: {
            Text(String.loc("A source repository can be mirrored to multiple targets. Choose a Git remote or filesystem archive (tar.gz, zip, or git bundle). Disabled targets are skipped during sync."))
                .font(.caption)
        }

        Section {
            FrequencyPickerView(frequency: $vm.frequency)
        } header: {
            Text(String.loc("Sync Frequency"))
        }

        Section {
            TagTokenInputView(
                tags: $vm.tags,
                suggestions: appVM.allKnownTags
            )
        } header: {
            Text(String.loc("Tags"))
        }

        Section {
            TextField("main", text: $vm.defaultBranch)
                .font(.system(.body, design: .monospaced))
            Text(String.loc("Integrity verification compares this branch's tip and tree hash on src and dst."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String.loc("Verification Branch"))
        }

        Section {
            Picker(String.loc("Policy"), selection: $vm.destructivePushPolicy) {
                ForEach(DestructivePushPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.segmented)

            Text(vm.destructivePushPolicy.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String.loc("Destructive Push Protection"))
        }

        Section {
            Toggle(String.loc("Mirror Releases and Binary Assets"), isOn: $vm.mirrorReleases)
            Text(String.loc("After syncing the git repository, incrementally copy source Release tags, titles, bodies, and attachments such as .dmg and .tar.gz files to each enabled target. A GitHub or GitLab API token is required."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String.loc("Release Mirroring"))
        }

        Section {
            Picker(String.loc("Git LFS"), selection: $vm.lfsMirrorMode) {
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
            Text(String.loc("Git LFS Objects"))
        }

        Section {
            Toggle(String.loc("Allow Instant Webhook Sync"), isOn: $vm.webhookEnabled)
            if vm.webhookEnabled {
                if let editing = editingRepo {
                    Text(String.loc("Path: /hook/\(editing.webhookPathID)"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    let url = appVM.webhookURL(for: editing)
                    HStack {
                        Text(url)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                        Button(String.loc("Copy URL")) { ClipboardService.copy(url) }
                            .font(.caption)
                    }

                    if let secret = WebhookSecretStore.loadSecret(repoID: editing.id) {
                        HStack {
                            Text(String.loc("HMAC secret saved in Keychain"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(String.loc("Copy Secret")) { ClipboardService.copy(secret) }
                                .font(.caption)
                        }
                    }
                } else {
                    Text(String.loc("Saving generates a /hook/<repo-id> path and an HMAC secret stored in Keychain. Also enable the local listener in Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(String.loc("Try to Register the Webhook Through the GitHub API When Saving"), isOn: $vm.registerWebhookOnSave)
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
            Text(String.loc("Webhook"))
        } footer: {
            Text(String.loc("Sync immediately after receiving a verified push event, independent of the frequency schedule. Enable the local listener in Settings → Webhook. Cloudflare Tunnel or Tailscale Funnel can optionally provide external access."))
        }

        Section {
            DisclosureGroup(String.loc("Advanced Options")) {
                TextField(String.loc("Clone Depth (Blank = Full History)"), text: $vm.depthText)
                    .font(.system(.body, design: .monospaced))
                if let err = vm.depthError {
                    Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                    Text(String.loc("Fetch Refspecs (One per Line)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $vm.refSpecsText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 72)
                }

                Text(String.loc("By default, all branches and tags are synced. You can limit this to main and v* tags, for example:\n+refs/heads/main:refs/heads/main\n+refs/tags/v*:refs/tags/v*"))
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
                Text(String.loc("GitRelay performs a dry run first. Strict Protection asks for confirmation before deletions or forced updates; canceling blocks the sync and records a failure. Run Automatically preserves traditional mirror behavior."))
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
            // Keep the user on the basics step when required fields fail.
            if vm.nameError != nil || vm.srcError != nil || !vm.targetErrors.isEmpty {
                vm.showsMoreOptions = false
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
        if runsPreflight {
            // Creates the empty destination first when that is what the button
            // promised; a failure stays on the caption line and keeps the sheet.
            guard await preflight.prepareDestinationForSave() else { return }
        }
        performSave()
    }

    private func refreshPreflight() {
        guard runsPreflight else { return }
        preflight.update(
            preflightInput,
            existingRepos: appVM.repos,
            excluding: vm.editingID
        )
    }

    /// Selects the pair GitRelay already mirrors and closes the sheet.
    private func openExistingPair() {
        guard let repoID = preflight.existingPairID else { return }
        appVM.pendingMainWindowRepoID = repoID
        dismiss()
    }

    private func performSave() {
        preflight.finish()
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
            return String.loc("Automatic webhook registration was skipped because no GitHub token was provided.")
        }
        guard let path = GitRemoteRepoPath.parse(from: repo.srcURL), !path.namespace.isEmpty else {
            return String.loc("Automatic webhook registration was skipped because owner/repo could not be parsed from the source URL.")
        }
        let client = GitHubWebhookAPIClient(token: trimmed)
        do {
            let scopes = try await client.fetchTokenScopes()
            let validation = ProviderTokenScope.validate(
                grantedScopes: scopes,
                usage: .webhookRegistration(provider: .github)
            )
            guard validation.isFullyAuthorized else {
                return String.loc("Automatic webhook registration was skipped because the token lacks admin:repo_hook.")
            }
            let secret = try WebhookSecretStore.ensureSecret(repoID: repo.id)
            let registration = try await client.createPushHook(
                owner: path.namespace,
                repo: path.name,
                hookURL: hookURL,
                secret: secret
            )
            return String.loc("Registered webhook #\(registration.id) on GitHub.")
        } catch {
            return String.loc("Automatic webhook registration failed: \(error.localizedDescription)")
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

/// Enables traffic-light chrome resize on the hosting sheet window (macOS 14+).
private struct ResizableSheetWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        window.minSize = minSize
    }
}
