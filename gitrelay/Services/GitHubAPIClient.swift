import Foundation

struct GitHubAPIClient: ProviderAPIClient {
    nonisolated let provider: GitProvider = .github
    nonisolated let token: String
    private nonisolated let session: URLSession = .shared

    nonisolated func fetchTokenScopes() async throws -> Set<String> {
        let (_, response) = try await rawRequest(path: "/user", query: [])
        guard let http = response as? HTTPURLResponse else {
            throw ProviderAPIError.http(status: -1, message: nil)
        }
        return ProviderTokenScope.parseGitHubOAuthScopesHeader(http.value(forHTTPHeaderField: "X-OAuth-Scopes"))
    }

    nonisolated func fetchRepos(scope: RemoteRepoScope, page: Int, perPage: Int) async throws -> RemoteRepoPage {
        let path: String
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "updated")
        ]
        switch scope {
        case .currentUser:
            path = "/user/repos"
            query.append(URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"))
        case .organization(let org):
            let encoded = org.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? org
            path = "/orgs/\(encoded)/repos"
            query.append(URLQueryItem(name: "type", value: "all"))
        }

        let dtos: [GitHubRepoDTO] = try await request(path: path, query: query)
        let repos = dtos.map(Self.toDomain)
        return RemoteRepoPage(repos: repos, hasMore: dtos.count == perPage, nextPage: page + 1)
    }

    // MARK: - Private

    private nonisolated func request<T: Decodable & Sendable>(path: String, query: [URLQueryItem]) async throws -> T {
        let (data, _) = try await rawRequest(path: path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(error)
        }
    }

    private nonisolated func rawRequest(path: String, query: [URLQueryItem]) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: provider.apiBaseURL.absoluteString + path)!
        components.queryItems = query
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ProviderAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderAPIError.http(status: -1, message: nil)
        }
        try Self.validate(status: http.statusCode, data: data)
        return (data, response)
    }

    private nonisolated static func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(GitHubErrorDTO.self, from: data))?.message
            switch status {
            case 401: throw ProviderAPIError.unauthorized(message)
            case 403: throw ProviderAPIError.forbidden(message)
            case 404: throw ProviderAPIError.notFound(message)
            default:  throw ProviderAPIError.http(status: status, message: message)
            }
        }
    }

    private nonisolated static func toDomain(_ dto: GitHubRepoDTO) -> RemoteRepo {
        RemoteRepo(
            id: String(dto.id),
            name: dto.name,
            fullName: dto.full_name,
            description: dto.description,
            isPrivate: dto.`private`,
            httpsCloneURL: dto.clone_url,
            sshCloneURL: dto.ssh_url,
            defaultBranch: dto.default_branch
        )
    }
}

private nonisolated struct GitHubRepoDTO: Decodable {
    let id: Int
    let name: String
    let full_name: String
    let description: String?
    let `private`: Bool
    let clone_url: String
    let ssh_url: String
    let default_branch: String?
}

private nonisolated struct GitHubErrorDTO: Decodable {
    let message: String?
}
