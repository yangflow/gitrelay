import Foundation

/// Repository lookup and empty-repository creation on GitHub (github.com or an
/// Enterprise host). Mirrors ``GiteaTargetAPIClient`` so the add sheet's
/// preflight can talk to any destination provider through one protocol.
struct GitHubTargetAPIClient: TargetProviderAPIClient {
    nonisolated let provider: GitProvider = .github
    nonisolated let baseURL: URL
    nonisolated let token: String
    private nonisolated let session: URLSession = .shared

    nonisolated init(baseURL: URL? = nil, token: String) {
        self.baseURL = baseURL ?? GitProvider.github.apiBaseURL
        self.token = token
    }

    nonisolated func fetchTokenScopes() async throws -> Set<String> {
        let (_, response) = try await send(makeRequest(path: "/user"))
        guard let http = response as? HTTPURLResponse else {
            throw TargetProviderAPIError.http(status: -1, message: nil)
        }
        return ProviderTokenScope.parseGitHubOAuthScopesHeader(http.value(forHTTPHeaderField: "X-OAuth-Scopes"))
    }

    nonisolated func fetchRepo(path: GitRemoteRepoPath) async throws -> TargetRepoLookup {
        do {
            let owned = try await ownerQualified(path)
            let dto: GitHubTargetRepoDTO = try await get(path: "/repos/\(Self.encodedPath(owned))")
            return .found(httpsCloneURL: dto.clone_url, sshCloneURL: dto.ssh_url)
        } catch TargetProviderAPIError.http(status: 404, message: _) {
            return .missing
        }
    }

    nonisolated func createRepo(
        name: String,
        namespace: TargetNamespace,
        isPrivate: Bool,
        description: String?
    ) async throws -> TargetCreateOutcome {
        let path = try await createPath(for: namespace)
        let body = GitHubCreateRepoRequest(
            name: name,
            description: description,
            private: isPrivate,
            auto_init: false
        )
        do {
            let dto: GitHubTargetRepoDTO = try await post(path: path, body: body)
            return .created(httpsCloneURL: dto.clone_url, sshCloneURL: dto.ssh_url)
        } catch TargetProviderAPIError.validation(let message) where Self.reportsExisting(message) {
            return try await existingRepo(name: name, namespace: namespace)
        }
    }

    // MARK: - Private

    /// A URL without an owner segment means the token's own account.
    private nonisolated func ownerQualified(_ path: GitRemoteRepoPath) async throws -> GitRemoteRepoPath {
        guard path.namespace.isEmpty else { return path }
        let me: GitHubTargetUserDTO = try await get(path: "/user")
        return GitRemoteRepoPath(namespace: me.login, name: path.name)
    }

    /// GitHub has no "create for another user" endpoint, and a personal
    /// namespace has to go through `/user/repos` rather than `/orgs/{owner}`.
    private nonisolated func createPath(for namespace: TargetNamespace) async throws -> String {
        switch namespace {
        case .currentUser:
            return "/user/repos"
        case .organization(let owner):
            let me: GitHubTargetUserDTO = try await get(path: "/user")
            if me.login.lowercased() == owner.lowercased() {
                return "/user/repos"
            }
            let encoded = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
            return "/orgs/\(encoded)/repos"
        case .adminForUser:
            throw TargetProviderAPIError.validation(
                String(localized: "GitHub cannot create a repository on behalf of another user.")
            )
        }
    }

    private nonisolated func existingRepo(
        name: String,
        namespace: TargetNamespace
    ) async throws -> TargetCreateOutcome {
        let owner: String
        switch namespace {
        case .currentUser:
            let me: GitHubTargetUserDTO = try await get(path: "/user")
            owner = me.login
        case .organization(let value), .adminForUser(let value):
            owner = value
        }
        let lookup = try await fetchRepo(path: GitRemoteRepoPath(namespace: owner, name: name))
        switch lookup {
        case .found(let https, let ssh):
            return .alreadyExists(httpsCloneURL: https, sshCloneURL: ssh)
        case .missing:
            throw TargetProviderAPIError.validation(
                String(localized: "GitHub reported the repository name as taken, but it could not be read back.")
            )
        }
    }

    private nonisolated static func reportsExisting(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.lowercased().contains("already exists")
    }

    private nonisolated static func encodedPath(_ path: GitRemoteRepoPath) -> String {
        path.pathWithNamespace
            .split(separator: "/")
            .map { segment in
                let value = String(segment)
                return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
            }
            .joined(separator: "/")
    }

    // MARK: - HTTP helpers

    private nonisolated func post<Req: Encodable & Sendable, Resp: Decodable & Sendable>(
        path: String,
        body: Req
    ) async throws -> Resp {
        var req = makeRequest(path: path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw TargetProviderAPIError.decoding(error)
        }
        return try await decode(req)
    }

    private nonisolated func get<Resp: Decodable & Sendable>(path: String) async throws -> Resp {
        try await decode(makeRequest(path: path))
    }

    private nonisolated func makeRequest(path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: baseURL.absoluteString + path) ?? baseURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        return req
    }

    private nonisolated func decode<Resp: Decodable & Sendable>(_ req: URLRequest) async throws -> Resp {
        let (data, _) = try await send(req)
        do {
            return try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw TargetProviderAPIError.decoding(error)
        }
    }

    private nonisolated func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw TargetProviderAPIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TargetProviderAPIError.http(status: -1, message: nil)
        }
        try Self.validate(status: http.statusCode, data: data)
        return (data, response)
    }

    private nonisolated static func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let message = Self.extractMessage(from: data)
            switch status {
            case 401: throw TargetProviderAPIError.unauthorized(message)
            case 403: throw TargetProviderAPIError.forbidden(message)
            case 422: throw TargetProviderAPIError.validation(message)
            default:  throw TargetProviderAPIError.http(status: status, message: message)
            }
        }
    }

    private nonisolated static func extractMessage(from data: Data) -> String? {
        if let dto = try? JSONDecoder().decode(GitHubTargetErrorDTO.self, from: data) {
            let details = (dto.errors ?? []).compactMap(\.message).joined(separator: "; ")
            let parts = [dto.message, details.isEmpty ? nil : details].compactMap { $0 }
            let joined = parts.joined(separator: ": ")
            if !joined.isEmpty { return joined }
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return body.count > 200 ? String(body.prefix(200)) + "…" : body
        }
        return nil
    }
}

private nonisolated struct GitHubCreateRepoRequest: Encodable {
    let name: String
    let description: String?
    let `private`: Bool
    let auto_init: Bool
}

private nonisolated struct GitHubTargetRepoDTO: Decodable {
    let name: String
    let full_name: String
    let clone_url: String
    let ssh_url: String
}

private nonisolated struct GitHubTargetUserDTO: Decodable {
    let login: String
}

private nonisolated struct GitHubTargetErrorDTO: Decodable {
    struct Detail: Decodable {
        let message: String?
    }

    let message: String?
    let errors: [Detail]?
}
