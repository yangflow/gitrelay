import AppKit
import SwiftUI

private enum AddMirrorSourceMode: String, CaseIterable, Identifiable {
    case connectedServices
    case gitURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connectedServices:
            String.loc("Browse Connected Services")
        case .gitURL:
            String.loc("Enter Git URL")
        }
    }
}

enum MirrorEditorPresentation {
    case sheet
    case window
}

struct MirrorEditorSheet: View {
    let editingRepo: MirrorSnapshot?
    let focusAuth: Bool
    let presentation: MirrorEditorPresentation

    @Environment(MirrorLibraryModel.self) private var library
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorManagementController.self) private var management
    @Environment(SecurityController.self) private var security
    @Environment(WebhookController.self) private var webhooks
    @Environment(AppIssueModel.self) private var issues
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var vm: MirrorEditorModel
    @State private var preflight: AddRepoPreflightViewModel
    @State private var browseVM: ConnectedServiceSourceModel
    @State private var sourceMode: AddMirrorSourceMode
    @State private var didScrollToAuth = false
    @State private var advancedExpanded = false
    @State private var scrollRequest: String?

    init(
        repo: MirrorSnapshot?,
        prefill: RepoSourceDropPrefill? = nil,
        focusAuth: Bool = false,
        defaultPolicy: MirrorDefaultPolicyPreferences = .default,
        presentation: MirrorEditorPresentation = .sheet
    ) {
        editingRepo = repo
        self.focusAuth = focusAuth
        self.presentation = presentation
        _vm = State(initialValue: MirrorEditorModel(
            editing: repo,
            prefill: prefill,
            defaultPolicy: defaultPolicy
        ))
        _preflight = State(initialValue: AddRepoPreflightViewModel())
        _browseVM = State(initialValue: ConnectedServiceSourceModel(defaultPolicy: defaultPolicy))
        _sourceMode = State(initialValue: prefill == nil && repo == nil ? .connectedServices : .gitURL)
    }

    private var title: String {
        editingRepo == nil ? String.loc("Add Mirror") : String.loc("Edit Mirror")
    }

    private var primaryActionTitle: String {
        guard editingRepo == nil else { return String.loc("Save") }
        if preflight.primaryAction == .createDestination {
            return AddPreflightCopy.createAndStartSyncTitle
        }
        return String.loc("Create and Start Mirror")
    }

    private var headerSubtitle: String {
        String.loc("Choose the source repository and its mirror destination.")
    }

    /// Preflight only runs while adding: an existing pair has already been probed
    /// by the sync engine itself.
    private var runsPreflight: Bool {
        editingRepo == nil
    }

    /// A pair GitRelay already mirrors replaces the primary action with open / add anyway.
    private var showsDuplicatePairChoice: Bool {
        runsPreflight && preflight.offersOpenExistingPair
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

    private var nameFieldBinding: Binding<String> {
        Binding(
            get: { vm.name },
            set: { vm.updateName($0) }
        )
    }

    @ViewBuilder
    var body: some View {
        if presentation == .sheet, #available(macOS 15.0, *) {
            activeSheetContent
                .presentationSizing(.fitted)
        } else {
            activeSheetContent
        }
    }

    @ViewBuilder
    private var activeSheetContent: some View {
        if editingRepo == nil, sourceMode == .connectedServices {
            browseSheetContent
        } else {
            sheetContent
        }
    }

    private var browseSheetContent: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            ConnectedServiceSourceView(
                vm: browseVM,
                onCancel: closeEditor,
                showsCancel: presentation == .sheet,
                onFinish: closeEditor
            )
        }
        .frame(
            minWidth: DesignTokens.Layout.addEditRepoSheetMinWidth,
            idealWidth: DesignTokens.Layout.addEditRepoSheetDefaultWidth,
            minHeight: DesignTokens.Layout.addEditRepoSheetMinHeight,
            idealHeight: DesignTokens.Layout.addEditRepoSheetDefaultHeight
        )
        .gitRelayChrome(.sheet)
        .background(ResizableSheetWindowConfigurator(
            minSize: NSSize(
                width: DesignTokens.Layout.addEditRepoSheetMinWidth,
                height: DesignTokens.Layout.addEditRepoSheetMinHeight
            )
        ))
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            sheetHeader

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    unifiedContent
                        .padding(DesignTokens.Spacing.sheetContent)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    scrollToAuthIfNeeded(proxy: proxy)
                }
                .onChange(of: scrollRequest) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .top)
                        scrollRequest = nil
                    }
                }
            }

            Divider()

            footer
        }
        .onAppear { refreshPreflight() }
        .onChange(of: preflightInput) { _, _ in refreshPreflight() }
        .onChange(of: library.mirrors.map(\.id)) { _, _ in refreshPreflight() }
        .onDisappear { preflight.cancel() }
        .frame(
            minWidth: DesignTokens.Layout.addEditRepoSheetMinWidth,
            idealWidth: DesignTokens.Layout.addEditRepoSheetDefaultWidth,
            minHeight: DesignTokens.Layout.addEditRepoSheetMinHeight,
            idealHeight: DesignTokens.Layout.addEditRepoSheetDefaultHeight
        )
        .gitRelayChrome(.sheet)
        .background(ResizableSheetWindowConfigurator(
            minSize: NSSize(
                width: DesignTokens.Layout.addEditRepoSheetMinWidth,
                height: DesignTokens.Layout.addEditRepoSheetMinHeight
            )
        ))
    }

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            if editingRepo == nil {
                Picker(String.loc("Source Selection"), selection: $sourceMode) {
                    ForEach(AddMirrorSourceMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                            .accessibilityIdentifier("add-mirror.source-mode.\(mode.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
                .accessibilityLabel(String.loc("Source Selection"))
                .accessibilityIdentifier("add-mirror.source-selection")
            }
        }
        .gitRelaySheetHeaderPadding()
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if presentation == .sheet {
                Button(String.loc("Cancel")) { closeEditor() }
                    .keyboardShortcut(.escape)
            }

            if showsDuplicatePairChoice {
                Spacer()

                Button(AddPreflightCopy.openExistingTitle) { openExistingPair() }

                Button(AddPreflightCopy.addAnywayTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            } else {
                Spacer()

                Button(primaryActionTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(preflight.isCreatingDestination)
                    .accessibilityIdentifier("add-mirror.primary-action")
            }
        }
        .gitRelaySheetFooterPadding()
    }

    private var unifiedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if focusAuth, editingRepo != nil {
                Text(String.loc("Update the token or SSH key for this mirror, then save."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            mirrorPathSection
            syncBehaviorSection
            advancedConfigurationSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var mirrorPathSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label(String.loc("Mirror Path"), systemImage: "arrow.triangle.branch")
                .font(.headline)
                .accessibilityIdentifier("add-mirror.mirror-path")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                        sourceEndpoint
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        Image(systemName: "arrow.right")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, height: 24)
                            .padding(.top, 25)
                            .accessibilityHidden(true)

                        targetsEndpoint
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        sourceEndpoint
                        Image(systemName: "arrow.down")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, DesignTokens.Spacing.xs)
                            .accessibilityHidden(true)
                        targetsEndpoint
                    }
                }

                if runsPreflight, let caption = preflight.caption {
                    Divider()
                    Label(caption, systemImage: preflightSymbolName)
                        .font(.caption)
                        .foregroundStyle(preflightTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .gitRelayPanelSurface(cornerRadius: DesignTokens.CornerRadius.panel)
        }
        .id(MirrorEditorScrollTarget.mirrorPath)
    }

    private var sourceEndpoint: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Label(String.loc("Source"), systemImage: "tray.and.arrow.down")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String.loc("Source URL"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $vm.srcURL,
                    prompt: Text("git@gitlab.com:org/repo.git")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

                if let err = vm.srcError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }

            AuthFieldView(
                label: String.loc("Source"),
                remoteURL: vm.srcURL,
                mode: $vm.srcAuthMode,
                keyPath: $vm.srcKeyPath,
                token: $vm.srcToken,
                pickerTitle: String.loc("Authentication Method")
            )
            .id(MirrorEditorScrollTarget.sourceAuth)
        }
    }

    private var targetsEndpoint: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Label(String.loc("Targets"), systemImage: "tray.and.arrow.up")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(vm.targets.enumerated()), id: \.element.id) { index, target in
                MirrorTargetFieldsView(
                    index: index,
                    target: binding(for: target.id),
                    error: vm.targetErrors[target.id],
                    canRemove: vm.targets.count > 1,
                    onRemove: { vm.removeTarget(id: target.id) },
                    showsHeader: vm.targets.count > 1,
                    showsEnabledToggle: editingRepo != nil,
                    urlFieldTitle: String.loc("Target URL"),
                    authPickerTitle: String.loc("Authentication Method")
                )

                if index < vm.targets.count - 1 {
                    Divider()
                }
            }

            Button {
                vm.addTarget()
            } label: {
                Label(String.loc("Add Target"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private var syncBehaviorSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label(String.loc("Sync Behavior"), systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                    frequencyControl
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Divider()
                    protectionControl
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    frequencyControl
                    Divider()
                    protectionControl
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .gitRelayPanelSurface(cornerRadius: DesignTokens.CornerRadius.panel)
        }
    }

    private var frequencyControl: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Text(String.loc("Sync Frequency"))
                .font(.subheadline.weight(.semibold))
            Picker(String.loc("Sync Frequency"), selection: $vm.frequency) {
                ForEach(SyncFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var protectionControl: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Text(String.loc("Destructive Push Protection"))
                .font(.subheadline.weight(.semibold))
            Picker(String.loc("Policy"), selection: $vm.destructivePushPolicy) {
                ForEach(DestructivePushPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text(vm.destructivePushPolicy.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var advancedConfigurationSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                advancedIdentityFields
                Divider()
                advancedContentFields
                Divider()
                automationFields
            }
            .padding(.top, DesignTokens.Spacing.md)
            .id(MirrorEditorScrollTarget.advancedContent)
        } label: {
            Label(String.loc("Advanced Configuration"), systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding(DesignTokens.Spacing.lg)
        .gitRelayPanelSurface(cornerRadius: DesignTokens.CornerRadius.panel)
        .id(MirrorEditorScrollTarget.advancedConfiguration)
    }

    private var advancedIdentityFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(String.loc("Name and Tags"))
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String.loc("Name"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("For example: my-project", text: nameFieldBinding)
                    .textFieldStyle(.roundedBorder)
                if let err = vm.nameError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String.loc("Tags"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TagTokenInputView(tags: $vm.tags, suggestions: management.allKnownTags)
            }
        }
    }

    private var advancedContentFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(String.loc("Content and Integrity"))
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String.loc("Verification Branch"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("main", text: $vm.defaultBranch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Text(String.loc("Integrity verification compares this branch's tip and tree hash on src and dst."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(String.loc("Verification Frequency"), selection: $vm.verificationFrequency) {
                ForEach(VerificationFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
            .pickerStyle(.menu)

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

            Toggle(String.loc("Mirror Releases and Binary Assets"), isOn: $vm.mirrorReleases)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String.loc("Clone Depth (Blank = Full History)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $vm.depthText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                if let err = vm.depthError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String.loc("Fetch Refspecs (One per Line)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $vm.refSpecsText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.control)
                            .stroke(Color.secondary.opacity(0.2))
                    }
                Text(String.loc("By default, all branches and tags are synced. You can limit this to main and v* tags, for example:\n+refs/heads/main:refs/heads/main\n+refs/tags/v*:refs/tags/v*"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = vm.partialSyncWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var automationFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(String.loc("Automation"))
                .font(.subheadline.weight(.semibold))

            Toggle(String.loc("Allow Instant Webhook Sync"), isOn: $vm.webhookEnabled)
            if vm.webhookEnabled {
                if let editing = editingRepo {
                    Text(String(format: String.loc("Path: /hook/%@"), editing.webhookPathID))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    let url = webhooks.displayURL(for: editing)
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
        }
    }

    private var preflightSymbolName: String {
        if preflight.isCreatingDestination { return "arrow.triangle.2.circlepath" }
        if preflight.isProbing { return "ellipsis" }
        switch preflight.decision {
        case .duplicatePair:
            return "doc.on.doc"
        case .destinationMissing:
            return "plus.circle"
        case .sourceMissing, .authenticationFailed:
            return "exclamationmark.triangle.fill"
        case .unreachable:
            return "wifi.exclamationmark"
        case .idle, .ready:
            return "checkmark.circle"
        }
    }

    private var preflightTint: Color {
        switch preflight.decision {
        case .sourceMissing, .authenticationFailed:
            return DesignTokens.StatusColor.error
        case .destinationMissing, .unreachable:
            return DesignTokens.StatusColor.warning
        case .duplicatePair:
            return DesignTokens.StatusColor.info
        case .idle, .ready:
            return Color.secondary
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
            if vm.depthError != nil || (vm.nameError != nil && vm.srcError == nil) {
                advancedExpanded = true
                scrollRequest = MirrorEditorScrollTarget.advancedConfiguration
            } else {
                scrollRequest = MirrorEditorScrollTarget.mirrorPath
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
                guard await security.authorize(action) else { return }
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
            existingRepos: library.mirrors,
            excluding: vm.editingID
        )
    }

    /// Selects the pair GitRelay already mirrors and closes the sheet.
    private func openExistingPair() {
        guard let repoID = preflight.existingPairID else { return }
        workspace.requestMirrorSelection(repoID)
        closeEditor()
    }

    private func performSave() {
        preflight.finish()
        let config = vm.buildMirrorSnapshot()
        vm.saveTokensToKeychain(repoID: config.id)
        vm.rememberLastUsedAuthMode()
        if editingRepo != nil {
            management.update(config)
        } else {
            management.add(config)
            operations.triggerSync(mirrorID: config.id)
        }

        if vm.webhookEnabled, vm.registerWebhookOnSave {
            let hookURL = webhooks.displayURL(for: config)
            let token = vm.webhookRegistrationToken
            Task {
                let message = await Self.registerGitHubWebhook(
                    repo: config,
                    hookURL: hookURL,
                    token: token
                )
                await MainActor.run {
                    if let message {
                        issues.report(message)
                    }
                }
            }
        }
        closeEditor()
    }

    private func closeEditor() {
        switch presentation {
        case .sheet:
            dismiss()
        case .window:
            dismissWindow(id: "add-mirror")
        }
    }

    private static func registerGitHubWebhook(
        repo: MirrorSnapshot,
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
            return String(format: String.loc("Registered webhook #%@ on GitHub."), registration.id)
        } catch {
            return String(format: String.loc("Automatic webhook registration failed: %@"), error.localizedDescription)
        }
    }

    private func scrollToAuthIfNeeded(proxy: ScrollViewProxy) {
        guard focusAuth, editingRepo != nil, !didScrollToAuth else { return }
        didScrollToAuth = true
        DispatchQueue.main.async {
            proxy.scrollTo(MirrorEditorScrollTarget.sourceAuth, anchor: .top)
        }
    }
}

private enum MirrorEditorScrollTarget {
    static let mirrorPath = "add-edit-mirror-path"
    static let sourceAuth = "add-edit-source-auth"
    static let advancedConfiguration = "add-edit-advanced-configuration"
    static let advancedContent = "add-edit-advanced-content"
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
