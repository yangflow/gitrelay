import Foundation

nonisolated enum ReleaseProviderAuth {
    static func resolveToken(for auth: AuthConfig, provider: GitProvider) -> String? {
        if case .httpsToken(let tag) = auth,
           let token = try? KeychainService.loadToken(tag: tag) {
            return token
        }
        return ProviderTokenStore.loadDefault(provider: provider)
    }

    static func apiBaseURL(for remoteURL: String, provider: GitProvider) -> URL {
        guard let host = GitRemoteHost.host(from: remoteURL) else {
            return provider.apiBaseURL
        }
        switch provider {
        case .github:
            if host == "github.com" {
                return GitProvider.github.apiBaseURL
            }
            return URL(string: "https://\(host)/api/v3")!
        case .gitlab:
            if host == "gitlab.com" {
                return GitProvider.gitlab.apiBaseURL
            }
            return URL(string: "https://\(host)/api/v4")!
        case .gitea:
            if host.hasSuffix("gitea.com") {
                return GitProvider.gitea.apiBaseURL
            }
            return URL(string: "https://\(host)/api/v1")!
        }
    }
}

protocol ReleaseProviderClient: Sendable {
    nonisolated var provider: GitProvider { get }
    nonisolated func listReleases(ownerRepo: String) async throws -> [ReleaseInfo]
    nonisolated func createRelease(ownerRepo: String, release: ReleaseInfo) async throws -> String
    nonisolated func fetchReleaseUploadURL(ownerRepo: String, tagName: String) async throws -> String?
    nonisolated func uploadAsset(
        ownerRepo: String,
        tagName: String,
        releaseUploadURL: String?,
        asset: ReleaseAssetInfo,
        data: Data
    ) async throws
}

enum ReleaseMirrorError: LocalizedError {
    case unsupportedProvider(GitProvider)
    case missingToken(String)
    case invalidRemoteURL(String)
    case assetUploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Release mirroring is not supported for \(provider.displayName)"
        case .missingToken(let side):
            return "Missing API token for \(side) — configure HTTPS token or save a provider token in Browse Remote"
        case .invalidRemoteURL(let url):
            return "Could not parse repository path from \(url)"
        case .assetUploadFailed(let name):
            return "Failed to upload asset \(name)"
        }
    }
}

struct ReleaseProviderClientFactory {
    nonisolated static func makeClient(
        remoteURL: String,
        auth: AuthConfig,
        side: String
    ) throws -> any ReleaseProviderClient {
        guard let provider = GitRemoteHost.inferredProvider(fromRemoteURL: remoteURL) else {
            throw ReleaseMirrorError.invalidRemoteURL(remoteURL)
        }
        guard provider == .github || provider == .gitlab else {
            throw ReleaseMirrorError.unsupportedProvider(provider)
        }
        guard let token = ReleaseProviderAuth.resolveToken(for: auth, provider: provider) else {
            throw ReleaseMirrorError.missingToken(side)
        }
        let baseURL = ReleaseProviderAuth.apiBaseURL(for: remoteURL, provider: provider)
        switch provider {
        case .github:
            return GitHubReleaseAPIClient(token: token, baseURL: baseURL)
        case .gitlab:
            return GitLabReleaseAPIClient(token: token, baseURL: baseURL)
        case .gitea:
            throw ReleaseMirrorError.unsupportedProvider(provider)
        }
    }
}
