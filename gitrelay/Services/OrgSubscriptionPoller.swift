import Foundation

/// Prefill payload for opening the browse-remote sheet after org discovery.
struct BrowseRemotePrefill: Equatable, Identifiable, Sendable {
    var id: UUID { subscriptionID }
    let subscriptionID: UUID
    let provider: GitProvider
    let accountLabel: String
    let organizationName: String
    let gitlabHost: String?
    let repos: [RemoteRepo]
    let preselectedRepoIDs: Set<String>
    let template: OrgSubscriptionTemplate
}

/// Result of checking one org subscription against the remote listing.
struct OrgSubscriptionCheckResult: Equatable, Sendable {
    let subscription: OrgSubscription
    let newRepos: [RemoteRepo]
    let allRemoteRepos: [RemoteRepo]
}

/// Fetches paginated remote repo listings (injectable for unit tests).
nonisolated struct OrgRemoteRepoFetcher: Sendable {
    var fetchPage: @Sendable (
        _ provider: GitProvider,
        _ token: String,
        _ gitlabBaseURL: URL?,
        _ scope: RemoteRepoScope,
        _ page: Int,
        _ perPage: Int
    ) async throws -> RemoteRepoPage

    static let live = OrgRemoteRepoFetcher { provider, token, gitlabBaseURL, scope, page, perPage in
        let client: any ProviderAPIClient = switch provider {
        case .github:
            GitHubAPIClient(token: token)
        case .gitlab:
            GitLabAPIClient(token: token, baseURL: gitlabBaseURL)
        case .gitea:
            preconditionFailure("Gitea is not a source listing provider")
        }
        return try await client.fetchRepos(scope: scope, page: page, perPage: perPage)
    }
}

/// Polls subscribed orgs/groups and diffs their repo lists against local mirrors.
@MainActor
final class OrgSubscriptionPoller {
    private let store: OrgSubscriptionStore
    private let fetcher: OrgRemoteRepoFetcher
    private let perPage = 50

    init(
        store: OrgSubscriptionStore,
        fetcher: OrgRemoteRepoFetcher? = nil
    ) {
        self.store = store
        self.fetcher = fetcher ?? .live
    }

    func checkAllSubscriptions(localRepos: [RepoConfig]) async -> [OrgSubscriptionCheckResult] {
        var results: [OrgSubscriptionCheckResult] = []
        for subscription in store.subscriptions {
            if let result = await checkSubscription(subscription, localRepos: localRepos) {
                results.append(result)
            }
        }
        return results
    }

    func checkSubscription(
        _ subscription: OrgSubscription,
        localRepos: [RepoConfig]
    ) async -> OrgSubscriptionCheckResult? {
        guard subscription.provider == .github || subscription.provider == .gitlab else { return nil }
        guard let token = ProviderTokenStore.load(
            provider: subscription.provider,
            accountLabel: subscription.accountLabel
        ) else {
            return nil
        }

        let gitlabBaseURL = resolvedGitLabBaseURL(
            provider: subscription.provider,
            accountLabel: subscription.accountLabel
        )

        do {
            let remoteRepos = try await fetchAllRepos(
                provider: subscription.provider,
                token: token,
                gitlabBaseURL: gitlabBaseURL,
                scope: subscription.scope
            )
            let newRepos = OrgRepoDiff.newRepos(remoteRepos: remoteRepos, localRepos: localRepos)
            store.markChecked(id: subscription.id)
            return OrgSubscriptionCheckResult(
                subscription: subscription,
                newRepos: newRepos,
                allRemoteRepos: remoteRepos
            )
        } catch {
            return nil
        }
    }

    private func fetchAllRepos(
        provider: GitProvider,
        token: String,
        gitlabBaseURL: URL?,
        scope: RemoteRepoScope
    ) async throws -> [RemoteRepo] {
        var all: [RemoteRepo] = []
        var page = 1
        var hasMore = true
        while hasMore {
            let result = try await fetcher.fetchPage(
                provider,
                token,
                gitlabBaseURL,
                scope,
                page,
                perPage
            )
            all.append(contentsOf: result.repos)
            hasMore = result.hasMore
            page = result.nextPage
        }
        return all
    }

    private func resolvedGitLabBaseURL(provider: GitProvider, accountLabel: String) -> URL? {
        guard provider == .gitlab else { return nil }
        guard let host = ProviderAccountStore.host(for: .gitlab, label: accountLabel) else { return nil }
        var normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if !normalized.hasPrefix("http://"), !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.hasSuffix("/api/v4") {
            normalized = String(normalized.dropLast("/api/v4".count))
        }
        return URL(string: normalized + "/api/v4")
    }
}
