import Foundation

struct GitLabAPIClient: ProviderAPIClient {
    nonisolated let provider: GitProvider = .gitlab
    nonisolated let token: String
    nonisolated let baseURL: URL
    private nonisolated let session: URLSession = .shared

    nonisolated init(token: String, baseURL: URL? = nil) {
        self.token = token
        self.baseURL = baseURL ?? GitProvider.gitlab.apiBaseURL
    }

    nonisolated func fetchRepos(scope: RemoteRepoScope, page: Int, perPage: Int) async throws -> RemoteRepoPage {
        let path: String
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "archived", value: "false")
        ]
        switch scope {
        case .currentUser:
            path = "/projects"
            query.append(URLQueryItem(name: "membership", value: "true"))
        case .organization(let group):
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encoded = group.addingPercentEncoding(withAllowedCharacters: allowed) ?? group
            path = "/groups/\(encoded)/projects"
            query.append(URLQueryItem(name: "include_subgroups", value: "true"))
        }

        let dtos: [GitLabProjectDTO] = try await request(path: path, query: query)
        let repos = dtos.map(Self.toDomain)
        return RemoteRepoPage(repos: repos, hasMore: dtos.count == perPage, nextPage: page + 1)
    }

    // MARK: - Private

    private nonisolated func request<T: Decodable & Sendable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: baseURL.absoluteString + path)!
        components.queryItems = query
        var req = URLRequest(url: components.url!)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
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

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(error)
        }
    }

    private nonisolated static func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let message = Self.extractMessage(from: data)
            switch status {
            case 401: throw ProviderAPIError.unauthorized(message)
            case 403: throw ProviderAPIError.forbidden(message)
            case 404: throw ProviderAPIError.notFound(message)
            default:  throw ProviderAPIError.http(status: status, message: message)
            }
        }
    }

    private nonisolated static func extractMessage(from data: Data) -> String? {
        if let dto = try? JSONDecoder().decode(GitLabErrorDTO.self, from: data) {
            if let m = dto.message, !m.isEmpty { return m }
            if let m = dto.error_description, !m.isEmpty { return m }
            if let m = dto.error, !m.isEmpty { return m }
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return body.count > 200 ? String(body.prefix(200)) + "…" : body
        }
        return nil
    }

    private nonisolated static func toDomain(_ dto: GitLabProjectDTO) -> RemoteRepo {
        RemoteRepo(
            id: String(dto.id),
            name: dto.path,
            fullName: dto.path_with_namespace,
            description: dto.description,
            isPrivate: (dto.visibility ?? "public") != "public",
            httpsCloneURL: dto.http_url_to_repo,
            sshCloneURL: dto.ssh_url_to_repo,
            defaultBranch: dto.default_branch
        )
    }
}

private nonisolated struct GitLabProjectDTO: Decodable {
    let id: Int
    let path: String
    let path_with_namespace: String
    let description: String?
    let visibility: String?
    let http_url_to_repo: String
    let ssh_url_to_repo: String
    let default_branch: String?
}

private nonisolated struct GitLabErrorDTO: Decodable {
    let message: String?
    let error: String?
    let error_description: String?
}
