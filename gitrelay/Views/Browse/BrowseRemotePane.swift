import SwiftUI

/// 浏览远程: the three-step browse-remote wizard, rendered in the main-window
/// right pane instead of a modal sheet.
///
/// The steps are unchanged — connect, pick, configure — and so is the batch
/// behaviour behind them. What changed is the chrome: grouped form sections,
/// host and account as popups, and a system list with real checkboxes.
struct BrowseRemotePane: View {
    @Environment(AppViewModel.self) private var appVM
    @Bindable var vm: BrowseRemoteRepoViewModel
    /// Called once the picked pairs are handed to the sync list.
    let onFinish: () -> Void

    @State private var isAddingSourceAccount = false
    @State private var isAddingTargetAccount = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeaderView(title: MainSidebarItem.browseRemote.title)

            BrowseRemoteStepBar(current: vm.step)
                .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
                .padding(.bottom, DesignTokens.Spacing.lg)

            stepHeading

            scopeBanner

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { vm.restoreContextIfNeeded() }
    }

    // MARK: - Heading

    private var stepHeading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
            Text(headingTitle)
                .font(.headline)
            Text(headingSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    private var headingTitle: String {
        switch vm.phase {
        case .submitting:
            String.loc("Creating Target Repositories")
        case .result:
            String.loc("Results")
        case .connect, .selecting, .configureTarget:
            vm.step.title
        }
    }

    private var headingSubtitle: String {
        switch vm.phase {
        case .submitting:
            String.loc("Processing \(vm.submitProgress) / \(vm.submitTotal)")
        case .result:
            String.loc("Review the outcome, then add the pairs to the sync list.")
        case .connect, .selecting, .configureTarget:
            vm.step.subtitle
        }
    }

    @ViewBuilder private var scopeBanner: some View {
        switch vm.phase {
        case .connect:
            TokenScopeBannerView(validation: vm.sourceScopeValidation)
        case .configureTarget where vm.targetAutoCreate:
            TokenScopeBannerView(validation: vm.targetScopeValidation)
        default:
            EmptyView()
        }
    }

    // MARK: - Content dispatch

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .connect:         connectView
        case .selecting:       selectView
        case .configureTarget: targetView
        case .submitting:      submittingView
        case .result:          resultView
        }
    }

    // MARK: - Step 1 — connect

    private var connectView: some View {
        Form {
            Section {
                Picker(String.loc("Host"), selection: $vm.provider) {
                    ForEach(GitProvider.listingCases) { candidate in
                        Label(candidate.displayName, systemImage: candidate.symbolName)
                            .tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: vm.provider) { _, _ in
                    vm.applyProviderChange()
                }

                accountRows(
                    labels: vm.sourceAccountLabels,
                    selectedLabel: vm.sourceAccountLabel,
                    isAdding: $isAddingSourceAccount,
                    canDelete: vm.canDeleteSourceAccount,
                    onSelect: { vm.selectSourceAccount($0) },
                    onCreate: { vm.createSourceAccount(label: $0) },
                    onDelete: { vm.deleteSourceAccount($0) }
                )
            } header: {
                Text(String.loc("Connection"))
            } footer: {
                accountFooter(canDelete: vm.canDeleteSourceAccount)
            }

            if vm.provider == .gitlab {
                Section {
                    TextField("https://gitlab.company.com", text: $vm.gitlabHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: vm.gitlabHost) { _, _ in
                            vm.persistGitLabHost()
                        }
                } header: {
                    Text(String.loc("GitLab Host"))
                } footer: {
                    Text(String.loc("Leave blank to use gitlab.com. The /api/v4 path is appended automatically."))
                        .font(.caption)
                }
            }

            Section {
                LabeledContent(String.loc("Token")) {
                    GatedSecureTokenField(
                        placeholder: "",
                        text: $vm.token
                    )
                    .onChange(of: vm.token) { _, _ in
                        vm.sourceScopeValidation = nil
                        vm.refreshCachedSourceScopeValidation()
                    }
                }
                Toggle(String.loc("Save to Keychain (Autofill Next Time)"), isOn: $vm.rememberToken)
            } footer: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(String.loc("Used only to fetch the repository list, not for git sync"))
                        .font(.caption)
                    Text(vm.provider.tokenHelpText)
                        .font(.caption)
                }
            }

            Section {
                Picker(String.loc("Select Scope"), selection: $vm.scopeKind) {
                    ForEach(BrowseRemoteRepoViewModel.ScopeKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: vm.scopeKind) { _, _ in
                    vm.refreshCachedSourceScopeValidation()
                }

                if vm.scopeKind == .organization {
                    TextField(
                        vm.provider == .github
                            ? "Organization name (for example, anthropic)"
                            : "Group path (for example, gitlab-org/charts)",
                        text: $vm.organizationName
                    )
                    .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text(String.loc("Scope"))
            }

            if let connectError = vm.connectError {
                Section {
                    errorLabel(connectError)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 2 — pick

    private var selectView: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search Names or Descriptions", text: $vm.searchText)
                    .textFieldStyle(.plain)
                Spacer(minLength: DesignTokens.Spacing.sm)
                Text(String.loc("\(vm.selectedIDs.count) selected"))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(String.loc("Select All Visible")) { vm.selectAllVisible() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Button(String.loc("Clear")) { vm.clearSelection() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(vm.selectedIDs.isEmpty)
            }
            .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            List {
                ForEach(vm.filteredRepos) { repo in
                    BrowseRemoteRepoRow(
                        repo: repo,
                        isSelected: vm.selectedIDs.contains(repo.id),
                        onToggle: { vm.toggleSelection(repo) }
                    )
                }
                if vm.hasMore {
                    HStack {
                        Spacer()
                        Button(vm.isLoading ? "Loading..." : "Load More") {
                            Task { await vm.loadMore() }
                        }
                        .disabled(vm.isLoading)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: DesignTokens.Layout.browseRepoListMinHeight)
        }
    }

    // MARK: - Step 3 — configure

    private var sourceRemoteURL: String? {
        vm.selectedRepos.first.map { vm.sourceURL(for: $0) }
    }

    private var targetRemoteURL: String? {
        vm.selectedRepos.first.map { vm.previewURL(for: $0) }
    }

    private var targetView: some View {
        Form {
            Section {
                AuthFieldView(
                    label: String.loc("Source"),
                    remoteURL: sourceRemoteURL,
                    mode: $vm.sourceAuthMode,
                    keyPath: $vm.sourceKeyPath,
                    token: $vm.sourceToken,
                    pickerTitle: String.loc("Authentication Method")
                )
            } header: {
                Text(String.loc("Source Repository Authentication (for git clone/fetch)"))
            } footer: {
                Text(String.loc("Source URLs come from the repositories you picked; this choice decides whether they use SSH or HTTPS."))
                    .font(.caption)
            }

            Section {
                Toggle(String.loc("Automatically Create Repositories on the Target (Gitea)"), isOn: $vm.targetAutoCreate)
                    .onChange(of: vm.targetAutoCreate) { _, enabled in
                        if enabled {
                            Task { await vm.prepareTargetConfiguration() }
                        } else {
                            vm.targetScopeValidation = nil
                        }
                    }
            } header: {
                Text(String.loc("Target Repository"))
            } footer: {
                Text(vm.targetAutoCreate
                     ? "Use the Gitea API to create the selected repositories in a batch; reuse existing repositories when names conflict."
                     : "Target repositories must already exist; URLs are generated with the {name} template.")
                    .font(.caption)
            }

            if vm.targetAutoCreate {
                autoCreateSections
            } else {
                Section {
                    TextField("git@github.com:myuser/{name}.git", text: $vm.targetURLTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                } header: {
                    Text(String.loc("Target URL Template"))
                } footer: {
                    Text(String.loc("Use {name} as the repository name placeholder."))
                        .font(.caption)
                }
            }

            Section {
                AuthFieldView(
                    label: String.loc("Target"),
                    remoteURL: targetRemoteURL,
                    mode: $vm.targetAuthMode,
                    keyPath: $vm.targetKeyPath,
                    token: $vm.targetToken,
                    pickerTitle: String.loc("Authentication Method")
                )
            } header: {
                Text(String.loc("Target Repository Authentication (for git push)"))
            }

            Section {
                TextField("Name Prefix (Optional)", text: $vm.namePrefix)
                    .textFieldStyle(.roundedBorder)
                FrequencyPickerView(frequency: $vm.frequency)
            } header: {
                Text(String.loc("Naming & Frequency"))
            }

            if !vm.selectedRepos.isEmpty {
                Section {
                    ForEach(vm.selectedRepos.prefix(3), id: \.id) { repo in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                            Text(vm.previewName(for: repo))
                                .font(.caption)
                                .bold()
                            Text(String.loc("src: \(vm.sourceURL(for: repo))"))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String.loc("dst: \(vm.previewURL(for: repo))"))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(String.loc("Preview (First 3)"))
                }
            }

            if let submitError = vm.submitError {
                Section {
                    errorLabel(submitError)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var autoCreateSections: some View {
        Section {
            accountRows(
                labels: vm.targetGiteaAccountLabels,
                selectedLabel: vm.targetGiteaAccountLabel,
                isAdding: $isAddingTargetAccount,
                canDelete: vm.canDeleteTargetGiteaAccount,
                onSelect: { vm.selectTargetGiteaAccount($0) },
                onCreate: { vm.createTargetGiteaAccount(label: $0) },
                onDelete: { vm.deleteTargetGiteaAccount($0) }
            )
        } header: {
            Text(String.loc("Gitea Account"))
        } footer: {
            accountFooter(canDelete: vm.canDeleteTargetGiteaAccount)
        }

        Section {
            TextField("https://gitea.company.com", text: $vm.targetCreateHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: vm.targetCreateHost) { _, _ in
                    vm.persistGiteaHost()
                    vm.targetScopeValidation = nil
                    vm.refreshCachedTargetScopeValidation()
                }
        } header: {
            Text(String.loc("Gitea Host"))
        } footer: {
            Text(String.loc("The /api/v1 path is appended automatically."))
                .font(.caption)
        }

        Section {
            GatedSecureTokenField(
                placeholder: "Requires the write:repository scope",
                text: $vm.targetCreateToken
            )
            .onChange(of: vm.targetCreateToken) { _, _ in
                vm.targetScopeValidation = nil
                vm.refreshCachedTargetScopeValidation()
            }
            Toggle(String.loc("Save to Keychain (Autofill Next Time)"), isOn: $vm.rememberTargetCreateToken)
        } header: {
            Text(String.loc("Gitea API Token"))
        }

        Section {
            Picker(String.loc("Location"), selection: $vm.targetNamespaceKind) {
                ForEach(BrowseRemoteRepoViewModel.NamespaceKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)

            if vm.targetNamespaceKind == .organization {
                TextField("Organization Name", text: $vm.targetNamespaceOwner)
                    .textFieldStyle(.roundedBorder)
            } else if vm.targetNamespaceKind == .adminForUser {
                TextField("Target Username (Token Must Be an Administrator)", text: $vm.targetNamespaceOwner)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(String.loc("Create as Private Repositories"), isOn: $vm.targetVisibilityPrivate)
        } header: {
            Text(String.loc("Namespace"))
        } footer: {
            if vm.targetNamespaceKind == .currentUser {
                Text(String.loc("Repositories will be created under the username associated with the current token."))
                    .font(.caption)
            }
        }
    }

    // MARK: - Submitting

    private var submittingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            ProgressView(value: submitFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: DesignTokens.Layout.browseStepBarMaxWidth)
                .accessibilityLabel(String.loc("Processing \(vm.submitProgress) / \(vm.submitTotal)"))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var submitFraction: Double {
        guard vm.submitTotal > 0 else { return 0 }
        return Double(vm.submitProgress) / Double(vm.submitTotal)
    }

    // MARK: - Result

    private var resultView: some View {
        let succeeded = vm.batchResults.reduce(into: 0) { acc, outcome in
            if case .success = outcome { acc += 1 }
        }
        let existed = vm.batchResults.reduce(into: 0) { acc, outcome in
            if case .success(_, _, let alreadyExists) = outcome, alreadyExists { acc += 1 }
        }
        let failed = vm.batchResults.reduce(into: 0) { acc, outcome in
            if case .failed = outcome { acc += 1 }
        }

        return Form {
            Section {
                HStack(spacing: DesignTokens.Spacing.lg) {
                    Label(String.loc("Succeeded \(succeeded)"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.StatusColor.success)
                    if existed > 0 {
                        Label(String.loc("Reused \(existed)"), systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(DesignTokens.StatusColor.info)
                    }
                    if failed > 0 {
                        Label(String.loc("Failed \(failed)"), systemImage: "xmark.octagon.fill")
                            .foregroundStyle(DesignTokens.StatusColor.error)
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }

            Section {
                ForEach(vm.batchResults) { outcome in
                    BrowseRemoteOutcomeRow(outcome: outcome)
                }
            } header: {
                Text(String.loc("Details"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if vm.phase.canGoBack {
                Button(String.loc("Back")) { vm.goBack() }
                    .buttonStyle(.bordered)
            }

            Spacer()

            if vm.phase == .result {
                Button(String.loc("Start Over")) { vm.startOver() }
            }

            primaryButton
        }
        .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    @ViewBuilder private var primaryButton: some View {
        switch vm.phase {
        case .connect:
            Button(vm.isLoading ? "Loading..." : "Load Repositories") {
                Task { await vm.loadFirstPage() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canAdvanceToSelect || vm.isLoading)
            .keyboardShortcut(.return)
        case .selecting:
            Button(String.loc("Next (\(vm.selectedIDs.count))")) {
                Task { await vm.advanceToTargetConfiguration() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedIDs.isEmpty)
            .keyboardShortcut(.return)
        case .configureTarget:
            Button(vm.targetAutoCreate
                   ? "Create and Add \(vm.selectedIDs.count)"
                   : "Add \(vm.selectedIDs.count) Repositories") {
                Task { await vm.runBatch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canSubmit)
            .keyboardShortcut(.return)
        case .submitting:
            EmptyView()
        case .result:
            let count = vm.successfulConfigs.count
            Button(String.loc("Add \(count) to Sync List")) {
                let configs = vm.successfulConfigs
                vm.persistTokensForSuccessfulConfigs()
                appVM.addRepos(configs, triggerSync: true)
                vm.startOver()
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
            .keyboardShortcut(.return)
        }
    }

    // MARK: - Shared rows

    /// Account popup plus a quiet add / remove row. Kept as loose rows rather
    /// than its own `View` so the enclosing `Section` still sees them.
    @ViewBuilder
    private func accountRows(
        labels: [String],
        selectedLabel: String,
        isAdding: Binding<Bool>,
        canDelete: Bool,
        onSelect: @escaping (String) -> Void,
        onCreate: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void
    ) -> some View {
        Picker(String.loc("Account"), selection: Binding(
            get: { selectedLabel },
            set: { onSelect($0) }
        )) {
            ForEach(labels, id: \.self) { label in
                Text(displayAccountLabel(label)).tag(label)
            }
        }
        .pickerStyle(.menu)

        if isAdding.wrappedValue {
            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("New account name (for example, work)", text: $vm.newAccountLabelInput)
                    .textFieldStyle(.roundedBorder)
                Button(String.loc("Add")) {
                    onCreate(vm.newAccountLabelInput)
                    isAdding.wrappedValue = false
                }
                .disabled(
                    BrowseRemoteAccountSelection.validatedNewLabel(
                        vm.newAccountLabelInput,
                        existing: labels
                    ) == nil
                )
                Button(String.loc("Cancel")) {
                    vm.newAccountLabelInput = ""
                    isAdding.wrappedValue = false
                }
                .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: DesignTokens.Spacing.md) {
                Button(String.loc("Add Account")) { isAdding.wrappedValue = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                if canDelete {
                    Button(String.loc("Remove Account"), role: .destructive) {
                        onDelete(selectedLabel)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func accountFooter(canDelete: Bool) -> some View {
        if let accountActionError = vm.accountActionError {
            Text(accountActionError)
                .font(.caption)
                .foregroundStyle(DesignTokens.StatusColor.error)
        } else if !canDelete {
            Text(String.loc("At least one account must remain."))
                .font(.caption)
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(DesignTokens.StatusColor.error)
    }

    private func displayAccountLabel(_ label: String) -> String {
        if label == ProviderAccount.defaultLabel {
            return String.loc("Default")
        }
        return label
    }
}

/// One remote repository in the step 2 picker: a stock macOS checkbox, no chip.
private struct BrowseRemoteRepoRow: View {
    let repo: RemoteRepo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(repo.fullName)
                        .lineLimit(1)
                    if repo.isPrivate {
                        Image(systemName: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(String.loc("Private repository"))
                            .accessibilityLabel(String.loc("Private repository"))
                    }
                }
                if let detail = repo.description, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, DesignTokens.Spacing.xxxs)
    }
}

private struct BrowseRemoteOutcomeRow: View {
    let outcome: BrowseRemoteRepoViewModel.BatchOutcome

    var body: some View {
        switch outcome {
        case .success(let repo, _, let alreadyExists):
            row(
                systemImage: alreadyExists
                    ? "arrow.counterclockwise.circle.fill"
                    : "checkmark.circle.fill",
                tint: alreadyExists
                    ? DesignTokens.StatusColor.info
                    : DesignTokens.StatusColor.success,
                title: repo.fullName,
                detail: alreadyExists
                    ? String.loc("Remote already exists and will be reused")
                    : String.loc("Created Successfully"),
                detailTint: .secondary
            )
        case .failed(let repo, let message):
            row(
                systemImage: "xmark.octagon.fill",
                tint: DesignTokens.StatusColor.error,
                title: repo.fullName,
                detail: message,
                detailTint: DesignTokens.StatusColor.error
            )
        }
    }

    private func row(
        systemImage: String,
        tint: Color,
        title: String,
        detail: String,
        detailTint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(title)
                    .font(.caption)
                    .bold()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(detailTint)
            }
            Spacer()
        }
    }
}
