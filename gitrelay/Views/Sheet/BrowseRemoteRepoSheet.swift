import SwiftUI

struct BrowseRemoteRepoSheet: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss
    @State private var vm = BrowseRemoteRepoViewModel()
    private let prefill: BrowseRemotePrefill?

    init(prefill: BrowseRemotePrefill? = nil) {
        self.prefill = prefill
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            scopeBanner
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640)
        .frame(minHeight: 560)
        .gitRelayChrome(.sheet)
        .onAppear {
            vm.refreshSourceAccounts()
            vm.refreshTargetGiteaAccounts()
            vm.restorePersistedToken()
            vm.restorePersistedTargetCreateToken()
            vm.refreshCachedSourceScopeValidation()
            vm.refreshCachedTargetScopeValidation()
            if let prefill {
                vm.applyPrefill(prefill)
            }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.popoverChromeVertical) {
            Text(headerTitle).font(.headline)
            Spacer()
            Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
        }
        .gitRelaySheetHeaderPadding()
    }

    private var headerTitle: String {
        switch vm.phase {
        case .connect:          String(localized: "Browse and Select Remote Repositories")
        case .selecting:        String(localized: "Select Repositories to Mirror")
        case .configureTarget:  String(localized: "Configure Target Repositories")
        case .submitting:       String(localized: "Creating Target Repositories")
        case .result:           String(localized: "Results")
        }
    }

    private var phaseLabel: String {
        switch vm.phase {
        case .connect:          "1 / 3"
        case .selecting:        "2 / 3"
        case .configureTarget:  "3 / 3"
        case .submitting:       String(localized: "Processing…")
        case .result:           String(localized: "Done")
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

    // MARK: - Phase 1

    private var connectView: some View {
        Form {
            Section {
                Picker("Type", selection: $vm.provider) {
                    ForEach(GitProvider.listingCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.provider) { _, _ in
                    vm.refreshSourceAccounts()
                    vm.restorePersistedToken()
                    vm.sourceScopeValidation = nil
                    vm.refreshCachedSourceScopeValidation()
                }

                accountSection(
                    labels: vm.sourceAccountLabels,
                    selectedLabel: vm.sourceAccountLabel,
                    onSelect: { vm.selectSourceAccount($0) },
                    onCreate: { vm.createSourceAccount(label: $0) },
                    onDelete: { vm.deleteSourceAccount($0) },
                    canDelete: vm.canDeleteSourceAccount
                )

                Text(vm.provider.tokenHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Provider")
            }

            if vm.provider == .gitlab {
                Section {
                    TextField("https://gitlab.company.com", text: $vm.gitlabHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: vm.gitlabHost) { _, _ in
                            vm.persistGitLabHost()
                        }
                    Text("Leave blank to use gitlab.com. The /api/v4 path is appended automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("GitLab Host (Self-Hosted Instance Optional)")
                }
            }

            if let accountError = vm.accountActionError {
                Section {
                    Label(accountError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }

            Section {
                GatedSecureTokenField(
                    placeholder: "Used only to fetch the repository list, not for git sync",
                    text: $vm.token
                )
                    .onChange(of: vm.token) { _, _ in
                        vm.sourceScopeValidation = nil
                        vm.refreshCachedSourceScopeValidation()
                    }
                Toggle("Save to Keychain (Autofill Next Time)", isOn: $vm.rememberToken)
            } header: {
                Text("Personal Access Token")
            }

            Section {
                Picker("Select Scope", selection: $vm.scopeKind) {
                    ForEach(BrowseRemoteRepoViewModel.ScopeKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.scopeKind) { _, _ in
                    vm.refreshCachedSourceScopeValidation()
                }

                if vm.scopeKind == .organization {
                    TextField(vm.provider == .github ? "Organization name (for example, anthropic)" : "Group path (for example, gitlab-org/charts)",
                              text: $vm.organizationName)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Scope")
            }

            if let err = vm.connectError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Phase 2

    private var selectView: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Names or Descriptions", text: $vm.searchText)
                    .textFieldStyle(.plain)
                Spacer()
                Button("Select All Visible") { vm.selectAllVisible() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Button("Clear") { vm.clearSelection() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            List {
                ForEach(vm.filteredRepos) { repo in
                    RepoPickerRow(
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
        }
    }

    // MARK: - Phase 3

    private var sourceRemoteURL: String? {
        vm.selectedRepos.first.map { vm.sourceURL(for: $0) }
    }

    private var targetRemoteURL: String? {
        vm.selectedRepos.first.map { vm.previewURL(for: $0) }
    }

    private var targetView: some View {
        Form {
            Section {
                Text("Source URLs are generated from the selected repositories (choose SSH or HTTPS with the source authentication option below)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("\(vm.selectedIDs.count) repositories selected")
            }

            Section {
                AuthFieldView(
                    label: "Source",
                    remoteURL: sourceRemoteURL,
                    mode: $vm.sourceAuthMode,
                    keyPath: $vm.sourceKeyPath,
                    token: $vm.sourceToken
                )
            } header: {
                Text("Source Repository Authentication (for git clone/fetch)")
            }

            Section {
                Toggle("Automatically Create Repositories on the Target (Gitea)", isOn: $vm.targetAutoCreate)
                    .onChange(of: vm.targetAutoCreate) { _, enabled in
                        if enabled {
                            Task { await vm.prepareTargetConfiguration() }
                        } else {
                            vm.targetScopeValidation = nil
                        }
                    }
                Text(vm.targetAutoCreate
                     ? "Use the Gitea API to create the selected repositories in a batch; reuse existing repositories when names conflict."
                     : "Target repositories must already exist; URLs are generated with the {name} template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Target Repository")
            }

            if vm.targetAutoCreate {
                autoCreateFields
            } else {
                Section {
                    TextField("git@github.com:myuser/{name}.git", text: $vm.targetURLTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Text("Use {name} as the repository name placeholder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Target URL Template")
                }
            }

            Section {
                AuthFieldView(
                    label: "Target",
                    remoteURL: targetRemoteURL,
                    mode: $vm.targetAuthMode,
                    keyPath: $vm.targetKeyPath,
                    token: $vm.targetToken
                )
            } header: {
                Text("Target Repository Authentication (for git push)")
            }

            Section {
                TextField("Name Prefix (Optional)", text: $vm.namePrefix)
                    .textFieldStyle(.roundedBorder)
                FrequencyPickerView(frequency: $vm.frequency)
            } header: {
                Text("Naming & Frequency")
            }

            if !vm.selectedRepos.isEmpty {
                Section {
                    ForEach(vm.selectedRepos.prefix(3), id: \.id) { repo in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                            Text(vm.previewName(for: repo)).font(.caption).bold()
                            Text("src: \(vm.sourceURL(for: repo))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("dst: \(vm.previewURL(for: repo))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Preview (First 3)")
                }
            }

            if let err = vm.submitError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var autoCreateFields: some View {
        accountSection(
            labels: vm.targetGiteaAccountLabels,
            selectedLabel: vm.targetGiteaAccountLabel,
            onSelect: { vm.selectTargetGiteaAccount($0) },
            onCreate: { vm.createTargetGiteaAccount(label: $0) },
            onDelete: { vm.deleteTargetGiteaAccount($0) },
            canDelete: vm.canDeleteTargetGiteaAccount
        )

        Section {
            TextField("https://gitea.company.com", text: $vm.targetCreateHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: vm.targetCreateHost) { _, _ in
                    vm.persistGiteaHost()
                }
            Text("The /api/v1 path is appended automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Gitea Host")
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
            Toggle("Save to Keychain (Autofill Next Time)", isOn: $vm.rememberTargetCreateToken)
        } header: {
            Text("Gitea API Token")
        }
        .onChange(of: vm.targetCreateHost) { _, _ in
            vm.targetScopeValidation = nil
            vm.refreshCachedTargetScopeValidation()
        }

        Section {
            Picker("Location", selection: $vm.targetNamespaceKind) {
                ForEach(BrowseRemoteRepoViewModel.NamespaceKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)

            switch vm.targetNamespaceKind {
            case .currentUser:
                Text("Repositories will be created under the username associated with the current token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .organization:
                TextField("Organization Name", text: $vm.targetNamespaceOwner)
                    .textFieldStyle(.roundedBorder)
            case .adminForUser:
                TextField("Target Username (Token Must Be an Administrator)", text: $vm.targetNamespaceOwner)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Create as Private Repositories", isOn: $vm.targetVisibilityPrivate)
        } header: {
            Text("Namespace")
        }
    }

    // MARK: - Phase 4 — submitting

    private var submittingView: some View {
        VStack(spacing: DesignTokens.Spacing.lg - DesignTokens.Spacing.xxxs) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Processing \(vm.submitProgress) / \(vm.submitTotal)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase 5 — result

    private var resultView: some View {
        let succeeded = vm.batchResults.reduce(into: 0) { acc, o in
            if case .success = o { acc += 1 }
        }
        let existed = vm.batchResults.reduce(into: 0) { acc, o in
            if case .success(_, _, let ex) = o, ex { acc += 1 }
        }
        let failed = vm.batchResults.reduce(into: 0) { acc, o in
            if case .failed = o { acc += 1 }
        }

        return Form {
            Section {
                HStack(spacing: DesignTokens.Spacing.lg - DesignTokens.Spacing.xxxs) {
                    Label("Succeeded \(succeeded)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.StatusColor.success)
                    if existed > 0 {
                        Label("Reused \(existed)", systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(DesignTokens.StatusColor.info)
                    }
                    if failed > 0 {
                        Label("Failed \(failed)", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(DesignTokens.StatusColor.error)
                    }
                }
                .font(.caption)
            }

            Section {
                ForEach(vm.batchResults) { outcome in
                    BatchOutcomeRow(outcome: outcome)
                }
            } header: {
                Text("Details")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if vm.phase != .connect, vm.phase != .submitting, vm.phase != .result {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if vm.phase != .submitting {
                Button(vm.phase == .result ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            primaryButton
        }
        .gitRelaySheetFooterPadding()
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
            Button("Next (\(vm.selectedIDs.count))") {
                vm.phase = .configureTarget
                Task { await vm.prepareTargetConfiguration() }
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
            Button("Add \(count) to Sync List") {
                let configs = vm.successfulConfigs
                vm.persistTokensForSuccessfulConfigs()
                appVM.addRepos(configs, triggerSync: true)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
            .keyboardShortcut(.return)
        }
    }

    private func goBack() {
        switch vm.phase {
        case .connect:          break
        case .selecting:        vm.phase = .connect
        case .configureTarget:  vm.phase = .selecting
        case .submitting:       break
        case .result:           break
        }
    }

    @ViewBuilder
    private func accountSection(
        labels: [String],
        selectedLabel: String,
        onSelect: @escaping (String) -> Void,
        onCreate: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void,
        canDelete: Bool
    ) -> some View {
        Section {
            Picker("Account", selection: Binding(
                get: { selectedLabel },
                set: { onSelect($0) }
            )) {
                ForEach(labels, id: \.self) { label in
                    Text(displayAccountLabel(label)).tag(label)
                }
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("New account name (for example, work)", text: $vm.newAccountLabelInput)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    onCreate(vm.newAccountLabelInput)
                }
                .disabled(
                    BrowseRemoteAccountSelection.validatedNewLabel(
                        vm.newAccountLabelInput,
                        existing: labels
                    ) == nil
                )
            }

            if canDelete {
                Button("Delete Current Account", role: .destructive) {
                    onDelete(selectedLabel)
                }
            } else {
                Text("At least one account must remain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Account")
        }
    }

    private func displayAccountLabel(_ label: String) -> String {
        if label == ProviderAccount.defaultLabel {
            return String(localized: "Default")
        }
        return label
    }
}

private struct RepoPickerRow: View {
    let repo: RemoteRepo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.popoverChromeVertical) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.system(size: DesignTokens.Size.menuBarIconPointSize))
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(repo.fullName).font(.caption).bold()
                        if repo.isPrivate {
                            Text("private")
                                .font(.caption2)
                                .padding(.horizontal, DesignTokens.Spacing.xxs)
                                .padding(.vertical, DesignTokens.Spacing.xxxs / 2)
                                .background(DesignTokens.Surface.chipFill)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.chip, style: .continuous))
                        }
                    }
                    if let d = repo.description, !d.isEmpty {
                        Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BatchOutcomeRow: View {
    let outcome: BrowseRemoteRepoViewModel.BatchOutcome

    var body: some View {
        switch outcome {
        case .success(let repo, _, let existed):
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: existed
                      ? "arrow.counterclockwise.circle.fill"
                      : "checkmark.circle.fill")
                    .foregroundStyle(existed ? DesignTokens.StatusColor.info : DesignTokens.StatusColor.success)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                    Text(repo.fullName).font(.caption).bold()
                    Text(existed ? "Remote already exists and will be reused" : "Created Successfully")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .failed(let repo, let message):
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(DesignTokens.StatusColor.error)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                    Text(repo.fullName).font(.caption).bold()
                    Text(message).font(.caption2).foregroundStyle(DesignTokens.StatusColor.error)
                }
                Spacer()
            }
        }
    }
}
