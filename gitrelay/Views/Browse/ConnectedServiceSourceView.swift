import AppKit
import SwiftUI

/// Connected-service source selection inside Add Mirror.
struct ConnectedServiceSourceView: View {
    @Environment(MirrorManagementController.self) private var management
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @Bindable var vm: ConnectedServiceSourceModel
    /// Closes Add Mirror without changing the library.
    let onCancel: () -> Void
    var showsCancel = true
    /// Called once the selected mirrors are added to the library.
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader

            scopeBanner

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { vm.restoreContextIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshConnections()
        }
    }

    // MARK: - Heading

    private var wizardHeader: some View {
        stepSummary
        .frame(maxWidth: DesignTokens.Layout.browseFormMaxWidth, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepSummary: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
            Text(headingTitle)
                .font(.headline)
            Text(headingSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headingTitle: String {
        switch vm.phase {
        case .connect:
            String.loc("Choose a Connected Service")
        case .selecting:
            String.loc("Choose Source Repositories")
        case .configureTarget:
            String.loc("Choose Destinations and Policy")
        case .submitting:
            String.loc("Creating Mirrors")
        case .result:
            String.loc("Results")
        }
    }

    private var headingSubtitle: String {
        switch vm.phase {
        case .connect:
            String.loc("Use an account already saved in Settings.")
        case .selecting:
            String.loc("Select one or more repositories. Your selection is kept while searching and paging.")
        case .configureTarget:
            String.loc("Preview generated mirror names and destinations before creation.")
        case .submitting:
            String(format: String.loc("Processing %lld / %lld"), vm.submitProgress, vm.submitTotal)
        case .result:
            String.loc("Review the outcome before closing Add Mirror.")
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
                        Label {
                            Text(candidate.displayName)
                        } icon: {
                            ProviderBrandIcon(provider: candidate)
                        }
                            .tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: vm.provider) { _, _ in
                    vm.applyProviderChange()
                }

                accountPicker(
                    labels: vm.sourceAccountLabels,
                    selectedLabel: vm.sourceAccountLabel,
                    onSelect: { vm.selectSourceAccount($0) }
                )
            } header: {
                Text(String.loc("Connection"))
            }

            if vm.provider == .gitlab {
                Section {
                    LabeledContent(String.loc("Host")) {
                        Text(vm.gitlabHost.isEmpty ? "gitlab.com" : vm.gitlabHost)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String.loc("GitLab Host"))
                } footer: {
                    Text(String.loc("Leave blank to use gitlab.com. The /api/v4 path is appended automatically."))
                        .font(.caption)
                }
            }

            Section {
                LabeledContent(String.loc("Credential")) {
                    Label(
                        vm.token.isEmpty
                            ? String.loc("Connection Required")
                            : String.loc("Ready"),
                        systemImage: vm.token.isEmpty
                            ? "exclamationmark.triangle"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        vm.token.isEmpty
                            ? DesignTokens.StatusColor.warning
                            : DesignTokens.StatusColor.success
                    )
                }
                Button(String.loc("Manage Connections…")) { openConnectionsSettings() }
            } footer: {
                Text(String.loc("Credentials are managed in Settings and remain in Keychain."))
                    .font(.caption)
            }

            Section {
                Picker(String.loc("Select Scope"), selection: $vm.scopeKind) {
                    ForEach(ConnectedServiceSourceModel.ScopeKind.allCases) { kind in
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
        .frame(maxWidth: DesignTokens.Layout.browseFormMaxWidth)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                Text(String(format: String.loc("%lld selected"), vm.selectedIDs.count))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(String.loc("Select All Visible")) { vm.selectAllVisible() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityIdentifier("add-mirror.connected.select-all")
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
                    ConnectedServiceRepositoryRow(
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
                        .accessibilityIdentifier("add-mirror.connected.target-template")
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
                            Text(String(format: String.loc("src: %@"), vm.sourceURL(for: repo)))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: String.loc("dst: %@"), vm.previewURL(for: repo)))
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
        .frame(maxWidth: DesignTokens.Layout.browseFormMaxWidth)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var autoCreateSections: some View {
        Section {
            accountPicker(
                labels: vm.targetGiteaAccountLabels,
                selectedLabel: vm.targetGiteaAccountLabel,
                onSelect: { vm.selectTargetGiteaAccount($0) }
            )
        } header: {
            Text(String.loc("Gitea Account"))
        }

        Section {
            LabeledContent(String.loc("Host")) {
                Text(vm.targetCreateHost.isEmpty ? String.loc("Not Configured") : vm.targetCreateHost)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(String.loc("Gitea Host"))
        } footer: {
            Text(String.loc("The /api/v1 path is appended automatically."))
                .font(.caption)
        }

        Section {
            Label(
                vm.targetCreateToken.isEmpty
                    ? String.loc("Connection Required")
                    : String.loc("Ready"),
                systemImage: vm.targetCreateToken.isEmpty
                    ? "exclamationmark.triangle"
                    : "checkmark.circle.fill"
            )
            Button(String.loc("Manage Connections…")) { openConnectionsSettings() }
        } header: {
            Text(String.loc("Credential"))
        } footer: {
            Text(String.loc("Repository creation uses the selected connection from Settings."))
                .font(.caption)
        }

        Section {
            Picker(String.loc("Location"), selection: $vm.targetNamespaceKind) {
                ForEach(ConnectedServiceSourceModel.NamespaceKind.allCases) { kind in
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

    private func openConnectionsSettings() {
        workspace.settingsPane = .connections
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Submitting

    private var submittingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            ProgressView(value: submitFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: DesignTokens.Layout.browseStepBarMaxWidth)
                .accessibilityLabel(String(format: String.loc("Processing %lld / %lld"), vm.submitProgress, vm.submitTotal))
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
                    Label(String(format: String.loc("Succeeded %lld"), succeeded), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.StatusColor.success)
                        .accessibilityIdentifier("add-mirror.connected.result-summary")
                    if existed > 0 {
                        Label(String(format: String.loc("Reused %lld"), existed), systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(DesignTokens.StatusColor.info)
                    }
                    if failed > 0 {
                        Label(String(format: String.loc("Failed %lld"), failed), systemImage: "xmark.octagon.fill")
                            .foregroundStyle(DesignTokens.StatusColor.error)
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }

            Section {
                ForEach(vm.batchResults) { outcome in
                    ConnectedServiceOutcomeRow(outcome: outcome)
                }
            } header: {
                Text(String.loc("Details"))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: DesignTokens.Layout.browseFormMaxWidth)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if showsCancel {
                Button(String.loc("Cancel"), role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape)
                    .accessibilityIdentifier("add-mirror.cancel")
            }

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
            Button(String(format: String.loc("Next (%lld)"), vm.selectedIDs.count)) {
                Task { await vm.advanceToTargetConfiguration() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedIDs.isEmpty)
            .keyboardShortcut(.return)
            .accessibilityIdentifier("add-mirror.connected.next")
        case .configureTarget:
            Button(vm.targetAutoCreate
                   ? "Create and Add \(vm.selectedIDs.count)"
                   : "Add \(vm.selectedIDs.count) Repositories") {
                Task { await vm.runBatch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canSubmit)
            .keyboardShortcut(.return)
            .accessibilityIdentifier("add-mirror.connected.submit")
        case .submitting:
            EmptyView()
        case .result:
            let count = vm.successfulConfigs.count
            Button(String(format: String.loc("Add %lld to Sync List"), count)) {
                let configs = vm.successfulConfigs
                vm.persistTokensForSuccessfulConfigs()
                management.add(contentsOf: configs, triggerSync: true)
                vm.startOver()
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
            .keyboardShortcut(.return)
            .accessibilityIdentifier("add-mirror.connected.finish")
        }
    }

    // MARK: - Shared rows

    private func accountPicker(
        labels: [String],
        selectedLabel: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        LabeledContent(String.loc("Account")) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Picker(String.loc("Account"), selection: Binding(
                    get: { selectedLabel },
                    set: { onSelect($0) }
                )) {
                    ForEach(labels, id: \.self) { label in
                        Text(displayAccountLabel(label)).tag(label)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
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
private struct ConnectedServiceRepositoryRow: View {
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
        .accessibilityIdentifier("connected-source.\(repo.id)")
        .padding(.vertical, DesignTokens.Spacing.xxxs)
    }
}

private struct ConnectedServiceOutcomeRow: View {
    let outcome: ConnectedServiceSourceModel.BatchOutcome

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
