import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class ConnectedServiceSourceModel {
    typealias Phase = ConnectedServiceSourcePhase

    enum ScopeKind: String, CaseIterable, Identifiable {
        case currentUser, organization
        var id: String { rawValue }
        var label: String {
            switch self {
            case .currentUser:  String.loc("My Repositories")
            case .organization: String.loc("Organization / Group")
            }
        }
    }

    enum NamespaceKind: String, CaseIterable, Identifiable {
        case currentUser, organization, adminForUser
        var id: String { rawValue }
        var label: String {
            switch self {
            case .currentUser:   String.loc("Current User")
            case .organization:  String.loc("Organization")
            case .adminForUser:  String.loc("Administrator Creates for User")
            }
        }
    }

    enum BatchOutcome: Identifiable {
        case success(repo: RemoteRepo, config: MirrorSnapshot, alreadyExists: Bool)
        case failed(repo: RemoteRepo, message: String)

        var id: String {
            switch self {
            case .success(let r, _, _): "s-" + r.id
            case .failed(let r, _):     "f-" + r.id
            }
        }

        var repo: RemoteRepo {
            switch self {
            case .success(let r, _, _): r
            case .failed(let r, _):     r
            }
        }
    }

    // Phase 1 — connect
    var provider: GitProvider = .github
    var sourceAccountLabel: String = ProviderAccount.defaultLabel
    var sourceAccountLabels: [String] = []
    var token: String = ""
    var scopeKind: ScopeKind = .currentUser
    var organizationName: String = ""
    var gitlabHost: String = ""
    var connectError: String?
    var isLoading: Bool = false
    var sourceScopeValidation: TokenScopeValidation?
    var targetScopeValidation: TokenScopeValidation?
    var isValidatingScopes: Bool = false

    // Phase 2 — selecting
    var repos: [RemoteRepo] = []
    var selectedIDs: Set<String> = []
    var searchText: String = ""
    var hasMore: Bool = false
    private var nextPage: Int = 1
    private let perPage: Int = 50

    // Phase 3 — target config (common)
    var sourceAuthMode: AuthMode = .sshAgent
    var sourceKeyPath: String = ""
    var sourceToken: String = ""
    var targetURLTemplate: String = ""
    var targetAuthMode: AuthMode = .sshAgent
    var targetKeyPath: String = ""
    var targetToken: String = ""
    var namePrefix: String = ""
    var frequency: SyncFrequency = .manual
    var defaultPolicy: MirrorDefaultPolicyPreferences
    var submitError: String?

    // Phase 3 — target auto-create
    var targetAutoCreate: Bool = false
    var targetGiteaAccountLabel: String = ProviderAccount.defaultLabel
    var targetGiteaAccountLabels: [String] = []
    var targetCreateHost: String = ""
    var targetCreateToken: String = ""
    var targetNamespaceKind: NamespaceKind = .currentUser
    var targetNamespaceOwner: String = ""
    var targetVisibilityPrivate: Bool = true

    // Phase 4/5 — submit + result
    var batchResults: [BatchOutcome] = []
    var submitProgress: Int = 0
    var submitTotal: Int = 0

    // Phase state
    var phase: Phase = .connect

    // MARK: - Derived

    var filteredRepos: [RemoteRepo] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter {
            $0.name.lowercased().contains(q) ||
            $0.fullName.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) ?? false)
        }
    }

    var selectedRepos: [RemoteRepo] {
        repos.filter { selectedIDs.contains($0.id) }
    }

    var canAdvanceToSelect: Bool {
        if token.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if scopeKind == .organization, organizationName.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    var canSubmit: Bool {
        guard !selectedIDs.isEmpty else { return false }
        if targetAutoCreate {
            if targetCreateHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if targetCreateToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if (targetNamespaceKind == .organization || targetNamespaceKind == .adminForUser),
               targetNamespaceOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            return true
        } else {
            return isValidTemplate(targetURLTemplate)
        }
    }

    var successfulConfigs: [MirrorSnapshot] {
        batchResults.compactMap { outcome in
            if case .success(_, let config, _) = outcome { return config } else { return nil }
        }
    }

    var hasFailures: Bool {
        batchResults.contains { if case .failed = $0 { true } else { false } }
    }

    // MARK: - Lifecycle

    private let accountDefaults: UserDefaults

    @ObservationIgnored private var didRestoreContext = false

    init(
        defaultPolicy: MirrorDefaultPolicyPreferences = .default,
        defaults: UserDefaults = .standard
    ) {
        self.accountDefaults = defaults
        self.defaultPolicy = defaultPolicy
        self.frequency = defaultPolicy.frequency
        ProviderAccountStore.ensureInitialized(defaults: defaults)
        refreshSourceAccounts()
        refreshTargetGiteaAccounts()
        restoreSourceAccountContext()
        restoreTargetGiteaAccountContext()
        #if DEBUG
        applyUITestFixtureIfNeeded()
        #endif
    }

    #if DEBUG
    private func applyUITestFixtureIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITRELAY_UI_TEST_MODE"] == "1",
              environment["GITRELAY_UI_TEST_FIXTURE"] == "batch" else { return }

        token = "ui-test-token"
        repos = [
            RemoteRepo(
                id: "example/alpha",
                name: "alpha",
                fullName: "example/alpha",
                description: "Primary service",
                isPrivate: false,
                httpsCloneURL: "https://github.com/example/alpha.git",
                sshCloneURL: "git@github.com:example/alpha.git",
                defaultBranch: "main"
            ),
            RemoteRepo(
                id: "example/beta",
                name: "beta",
                fullName: "example/beta",
                description: "Secondary service",
                isPrivate: true,
                httpsCloneURL: "https://github.com/example/beta.git",
                sshCloneURL: "git@github.com:example/beta.git",
                defaultBranch: "main"
            )
        ]
        targetURLTemplate = "git@gitlab.com:backup/{name}.git"
        phase = .selecting
    }
    #endif

    /// Re-reads accounts, tokens, and cached scopes the first time the pane
    /// appears. The wizard outlives the pane, so later appearances must not
    /// overwrite a token the user is midway through typing.
    func restoreContextIfNeeded() {
        guard !didRestoreContext else { return }
        didRestoreContext = true
        refreshSourceAccounts()
        refreshTargetGiteaAccounts()
        restoreSourceAccountContext()
        restoreTargetGiteaAccountContext()
    }

    /// Refreshes connection records after Settings closes without clearing the
    /// selected repositories, target draft, search, or current phase.
    func refreshConnections() {
        refreshSourceAccounts()
        refreshTargetGiteaAccounts()
        restoreSourceAccountContext()
        restoreTargetGiteaAccountContext()
    }

    /// Selects the connected service before the Add Mirror source picker appears.
    func selectProvider(_ newValue: GitProvider) {
        guard GitProvider.listingCases.contains(newValue), newValue != provider else { return }
        provider = newValue
        applyProviderChange()
    }

    /// Reloads the account list and token after the host popup changes.
    func applyProviderChange() {
        refreshSourceAccounts()
        restoreSourceAccountContext()
    }

    // MARK: - Navigation

    func goBack() {
        guard let previous = phase.previous else { return }
        phase = previous
    }

    func advanceToTargetConfiguration() async {
        phase = .configureTarget
        await prepareTargetConfiguration()
    }

    /// Returns the source picker to its first phase without discarding the connected account,
    /// host, or token, so a second batch does not start from nothing.
    func startOver() {
        phase = .connect
        repos = []
        selectedIDs = []
        searchText = ""
        hasMore = false
        nextPage = 1
        batchResults = []
        submitProgress = 0
        submitTotal = 0
        connectError = nil
        submitError = nil
    }

    func refreshSourceAccounts() {
        sourceAccountLabels = ProviderAccountStore.accountLabels(for: provider, defaults: accountDefaults)
        sourceAccountLabel = ProviderAccountStore.selectedLabel(for: provider, defaults: accountDefaults)
    }

    func refreshTargetGiteaAccounts() {
        targetGiteaAccountLabels = ProviderAccountStore.accountLabels(for: .gitea, defaults: accountDefaults)
        targetGiteaAccountLabel = ProviderAccountStore.selectedLabel(for: .gitea, defaults: accountDefaults)
    }

    func selectSourceAccount(_ label: String) {
        guard sourceAccountLabels.contains(label) else { return }
        sourceAccountLabel = label
        ProviderAccountStore.setSelectedLabel(label, for: provider, defaults: accountDefaults)
        restoreSourceAccountContext()
    }

    func selectTargetGiteaAccount(_ label: String) {
        guard targetGiteaAccountLabels.contains(label) else { return }
        targetGiteaAccountLabel = label
        ProviderAccountStore.setSelectedLabel(label, for: .gitea, defaults: accountDefaults)
        restoreTargetGiteaAccountContext()
    }

    func restorePersistedToken() {
        restoreSourceAccountContext()
    }

    func restorePersistedTargetCreateToken() {
        restoreTargetGiteaAccountContext()
    }

    private func restoreSourceAccountContext() {
        sourceAccountLabel = ProviderAccountStore.selectedLabel(for: provider, defaults: accountDefaults)
        if let saved = ProviderTokenStore.load(provider: provider, accountLabel: sourceAccountLabel) {
            token = saved
        } else {
            token = ""
        }
        gitlabHost = ProviderAccountStore.host(for: .gitlab, label: sourceAccountLabel, defaults: accountDefaults) ?? ""
        sourceScopeValidation = nil
        refreshCachedSourceScopeValidation()
    }

    private func restoreTargetGiteaAccountContext() {
        targetGiteaAccountLabel = ProviderAccountStore.selectedLabel(for: .gitea, defaults: accountDefaults)
        if let saved = ProviderTokenStore.load(provider: .gitea, accountLabel: targetGiteaAccountLabel) {
            targetCreateToken = saved
        } else {
            targetCreateToken = ""
        }
        targetCreateHost = ProviderAccountStore.host(for: .gitea, label: targetGiteaAccountLabel, defaults: accountDefaults) ?? ""
        targetScopeValidation = nil
        refreshCachedTargetScopeValidation()
    }

    func refreshCachedSourceScopeValidation() {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            sourceScopeValidation = nil
            return
        }
        let key = sourceScopeCacheKey(token: clean)
        if let cached = ProviderTokenScopeCache.load(key: key) {
            sourceScopeValidation = ProviderTokenScope.validate(
                grantedScopes: cached,
                usage: sourceTokenUsage
            )
        } else {
            sourceScopeValidation = nil
        }
    }

    func refreshCachedTargetScopeValidation() {
        let clean = targetCreateToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            targetScopeValidation = nil
            return
        }
        let key = targetScopeCacheKey(token: clean)
        if let cached = ProviderTokenScopeCache.load(key: key) {
            targetScopeValidation = ProviderTokenScope.validate(
                grantedScopes: cached,
                usage: .giteaTargetCreate
            )
        } else {
            targetScopeValidation = nil
        }
    }

    func validateSourceTokenScopes(forceRefresh: Bool = false) async {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            sourceScopeValidation = nil
            return
        }

        isValidatingScopes = true
        defer { isValidatingScopes = false }

        do {
            sourceScopeValidation = try await ProviderTokenScope.resolveScopes(
                usage: sourceTokenUsage,
                cacheKey: sourceScopeCacheKey(token: clean),
                forceRefresh: forceRefresh
            ) {
                try await self.client(for: clean).fetchTokenScopes()
            }
        } catch {
            sourceScopeValidation = nil
            if connectError == nil {
                connectError = (error as? ProviderAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func validateTargetTokenScopes(forceRefresh: Bool = false) async {
        let clean = targetCreateToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let baseURL = resolvedGiteaBaseURL() else {
            targetScopeValidation = nil
            return
        }

        isValidatingScopes = true
        defer { isValidatingScopes = false }

        do {
            targetScopeValidation = try await ProviderTokenScope.resolveScopes(
                usage: .giteaTargetCreate,
                cacheKey: targetScopeCacheKey(token: clean),
                forceRefresh: forceRefresh
            ) {
                let client = GiteaTargetAPIClient(baseURL: baseURL, token: clean)
                return try await client.fetchTokenScopes()
            }
        } catch {
            targetScopeValidation = nil
        }
    }

    // MARK: - Load

    func loadFirstPage() async {
        connectError = nil
        isLoading = true
        defer { isLoading = false }

        await validateSourceTokenScopes()
        guard connectError == nil else { return }

        repos = []
        selectedIDs = []
        nextPage = 1
        hasMore = false

        do {
            let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = try await client(for: clean).fetchRepos(scope: currentScope, page: nextPage, perPage: perPage)
            repos = page.repos
            hasMore = page.hasMore
            nextPage = page.nextPage
            phase = .selecting
            // The account's token just listed repositories, which is what the
            // 安全 tab reports as 最后使用.
            ProviderAccountStore.markUsed(
                for: provider,
                label: sourceAccountLabel,
                defaults: accountDefaults
            )
        } catch {
            connectError = (error as? ProviderAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = try await client(for: clean).fetchRepos(scope: currentScope, page: nextPage, perPage: perPage)
            repos.append(contentsOf: page.repos)
            hasMore = page.hasMore
            nextPage = page.nextPage
        } catch {
            connectError = (error as? ProviderAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func prepareTargetConfiguration() async {
        if targetAutoCreate {
            await validateTargetTokenScopes()
        } else {
            targetScopeValidation = nil
        }
    }

    // MARK: - Selection helpers

    func toggleSelection(_ repo: RemoteRepo) {
        if selectedIDs.contains(repo.id) {
            selectedIDs.remove(repo.id)
        } else {
            selectedIDs.insert(repo.id)
        }
    }

    func selectAllVisible() {
        filteredRepos.forEach { selectedIDs.insert($0.id) }
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    // MARK: - Template preview

    func previewURL(for repo: RemoteRepo) -> String {
        if targetAutoCreate {
            let host = normalizedHostOnly(targetCreateHost)
            let owner = resolvedOwner()
            let name = previewName(for: repo)
            switch targetAuthMode {
            case .sshAgent, .sshKey: return "git@\(host):\(owner)/\(name).git"
            case .httpsToken:        return "https://\(host)/\(owner)/\(name).git"
            }
        }
        return render(template: targetURLTemplate, repo: repo)
    }

    func previewName(for repo: RemoteRepo) -> String {
        namePrefix + repo.name
    }

    func sourceURL(for repo: RemoteRepo) -> String {
        switch sourceAuthMode {
        case .sshAgent, .sshKey: repo.sshCloneURL
        case .httpsToken:        repo.httpsCloneURL
        }
    }

    // MARK: - Submit batch

    func runBatch() async {
        phase = .submitting
        batchResults = []
        submitProgress = 0
        submitTotal = selectedRepos.count

        if targetAutoCreate {
            await validateTargetTokenScopes()
        }

        let selected = selectedRepos
        for repo in selected {
            submitProgress += 1
            if targetAutoCreate {
                await createAndBuildConfig(for: repo)
            } else {
                buildConfigFromTemplate(for: repo)
            }
        }

        phase = .result
    }

    func persistTokensForSuccessfulConfigs() {
        for config in successfulConfigs {
            if case .httpsToken(let tag) = config.srcAuth, !sourceToken.isEmpty {
                try? KeychainService.saveToken(sourceToken, tag: tag)
            }
            for target in config.targets {
                if case .httpsToken(let tag) = target.auth, !targetToken.isEmpty {
                    try? KeychainService.saveToken(targetToken, tag: tag)
                }
            }
        }
    }

    // MARK: - Private — batch helpers

    private func createAndBuildConfig(for repo: RemoteRepo) async {
        guard let baseURL = resolvedGiteaBaseURL() else {
            batchResults.append(.failed(repo: repo, message: String.loc("The target API host is invalid")))
            return
        }
        let client = GiteaTargetAPIClient(
            baseURL: baseURL,
            token: targetCreateToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let name = previewName(for: repo)
        do {
            let outcome = try await client.createRepo(
                name: name,
                namespace: currentTargetNamespace(),
                isPrivate: targetVisibilityPrivate,
                description: repo.description
            )
            let (httpsURL, sshURL, existed): (String, String, Bool) = {
                switch outcome {
                case .created(let h, let s):        return (h, s, false)
                case .alreadyExists(let h, let s):  return (h, s, true)
                }
            }()
            let dstURL: String = {
                switch targetAuthMode {
                case .sshAgent, .sshKey: return sshURL
                case .httpsToken:        return httpsURL
                }
            }()
            let config = makeConfig(repo: repo, dstURL: dstURL)
            batchResults.append(.success(repo: repo, config: config, alreadyExists: existed))
            ProviderAccountStore.markUsed(
                for: .gitea,
                label: targetGiteaAccountLabel,
                defaults: accountDefaults
            )
        } catch {
            let msg = (error as? TargetProviderAPIError)?.errorDescription ?? error.localizedDescription
            batchResults.append(.failed(repo: repo, message: msg))
        }
    }

    private func buildConfigFromTemplate(for repo: RemoteRepo) {
        let dstURL = render(template: targetURLTemplate, repo: repo)
        let config = makeConfig(repo: repo, dstURL: dstURL)
        batchResults.append(.success(repo: repo, config: config, alreadyExists: false))
    }

    private func makeConfig(repo: RemoteRepo, dstURL: String) -> MirrorSnapshot {
        let id = UUID()
        let targetID = UUID()
        return MirrorSnapshot(
            id: id,
            name: previewName(for: repo),
            srcURL: sourceURL(for: repo),
            targets: [
                MirrorTarget(
                    id: targetID,
                    url: dstURL,
                    auth: buildAuth(
                        mode: targetAuthMode,
                        keyPath: targetKeyPath,
                        repoID: id,
                        side: "target-\(targetID.uuidString)"
                    )
                )
            ],
            srcAuth: buildAuth(mode: sourceAuthMode, keyPath: sourceKeyPath, repoID: id, side: "src"),
            frequency: frequency,
            destructivePushPolicy: defaultPolicy.destructivePush,
            mirrorReleases: defaultPolicy.mirrorsReleases,
            lfsMirrorMode: defaultPolicy.lfsMode,
            webhookEnabled: defaultPolicy.webhookEnabled,
            verificationFrequency: defaultPolicy.verificationFrequency
        )
    }

    private func currentTargetNamespace() -> TargetNamespace {
        switch targetNamespaceKind {
        case .currentUser:  return .currentUser
        case .organization: return .organization(targetNamespaceOwner.trimmingCharacters(in: .whitespacesAndNewlines))
        case .adminForUser: return .adminForUser(targetNamespaceOwner.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Private — host/URL normalization

    private var currentScope: RemoteRepoScope {
        switch scopeKind {
        case .currentUser:  .currentUser
        case .organization: .organization(organizationName.trimmingCharacters(in: .whitespaces))
        }
    }

    private var sourceTokenUsage: ProviderTokenUsage {
        .sourceListing(
            provider: provider,
            organizationScope: scopeKind == .organization
        )
    }

    private func sourceScopeCacheKey(token: String) -> String {
        ProviderTokenScopeCache.cacheKey(
            provider: provider,
            token: token,
            baseURL: provider == .gitlab ? resolvedGitLabBaseURL() : nil
        )
    }

    private func targetScopeCacheKey(token: String) -> String {
        ProviderTokenScopeCache.cacheKey(
            provider: .gitea,
            token: token,
            baseURL: resolvedGiteaBaseURL()
        )
    }

    private func client(for token: String) -> any ProviderAPIClient {
        switch provider {
        case .github:
            return GitHubAPIClient(token: token)
        case .gitlab:
            return GitLabAPIClient(token: token, baseURL: resolvedGitLabBaseURL())
        case .gitea:
            preconditionFailure("Gitea is target-only; source picker must use GitProvider.listingCases.")
        }
    }

    private func client() -> any ProviderAPIClient {
        client(for: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func resolvedGitLabBaseURL() -> URL? {
        ProviderAPIBaseURL.resolve(provider: .gitlab, host: gitlabHost)
    }

    private func resolvedGiteaBaseURL() -> URL? {
        ProviderAPIBaseURL.resolve(provider: .gitea, host: targetCreateHost)
    }

    private func normalizedHostOnly(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("https://") { host.removeFirst("https://".count) }
        else if host.hasPrefix("http://") { host.removeFirst("http://".count) }
        while host.hasSuffix("/") { host.removeLast() }
        if host.hasSuffix("/api/v1") { host = String(host.dropLast("/api/v1".count)) }
        while host.hasSuffix("/") { host.removeLast() }
        return host
    }

    private func resolvedOwner() -> String {
        switch targetNamespaceKind {
        case .currentUser:   return "<user>"
        case .organization:  return targetNamespaceOwner.isEmpty ? "<org>" : targetNamespaceOwner
        case .adminForUser:  return targetNamespaceOwner.isEmpty ? "<user>" : targetNamespaceOwner
        }
    }

    private func isValidTemplate(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("{name}") else { return false }
        if trimmed.hasPrefix("git@") { return true }
        if let u = URL(string: trimmed.replacingOccurrences(of: "{name}", with: "x")), u.scheme == "https" { return true }
        return false
    }

    private func render(template: String, repo: RemoteRepo) -> String {
        template.replacingOccurrences(of: "{name}", with: repo.name)
    }

    private func buildAuth(mode: AuthMode, keyPath: String, repoID: UUID, side: String) -> AuthConfig {
        switch mode {
        case .sshAgent:   .sshAgent
        case .sshKey:     .sshKey(privateKeyPath: keyPath)
        case .httpsToken: .httpsToken(keychainTag: "\(repoID.uuidString)-\(side)")
        }
    }
}
