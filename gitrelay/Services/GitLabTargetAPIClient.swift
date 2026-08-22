import Foundation

/// Project lookup and empty-project creation on GitLab (gitlab.com or a
/// self-hosted instance), behind the same protocol as the other destination
/// providers.
struct GitLabTargetAPIClient: TargetProviderAPIClient {
    nonisolated let provider: GitProvider = .gitlab
    nonisolated let baseURL: URL
    nonisolated let token: String
    private nonisolated let session: URLSession = .shared

    nonisolated init(baseURL: URL? = nil, token: String) {
        self.baseURL = baseURL ?? GitProvider.gitlab.apiBaseURL
        self.token = token
    }

    nonisolated func fetchTokenScopes() async throws -> Set<String> {
        let dto: GitLabTargetTokenDTO = try await get(path: "/personal_access_tokens/self", query: [])
        return ProviderTokenScope.parseGitLabScopes(dto.scopes)
    }

    nonisolated func fetchRepo(path: GitRemoteRepoPath) async throws -> TargetRepoLookup {
        do {
            let owned = try await ownerQualified(path)
            let dto: GitLabTargetProjectDTO = try await get(
                path: "/projects/\(Self.encodedFullPath(owned.pathWithNamespace))",
                query: []
            )
            return .found(httpsCloneURL: dto.http_url_to_repo, sshCloneURL: dto.ssh_url_to_repo)
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
        let body = GitLabCreateProjectRequest(
            name: name,
            path: name,
            description: description,
            visibility: isPrivate ? "private" : "public",
            namespace_id: try await namespaceID(for: namespace),
            initialize_with_readme: false
        )
        do {
            let dto: GitLabTargetProjectDTO = try await post(path: "/projects", body: body)
            return .created(httpsCloneURL: dto.http_url_to_repo, sshCloneURL: dto.ssh_url_to_repo)
        } catch TargetProviderAPIError.validation(let message) where Self.reportsExisting(message) {
            return try await existingProject(name: name, namespace: namespace)
        }
    }

    // MARK: - Private

    /// A URL without an owner segment means the token's own namespace.
    private nonisolated func ownerQualified(_ path: GitRemoteRepoPath) async throws -> GitRemoteRepoPath {
        guard path.namespace.isEmpty else { return path }
        let me: GitLabTargetUserDTO = try await get(path: "/user", query: [])
        return GitRemoteRepoPath(namespace: me.username, name: path.name)
    }

    /// A group or user namespace has to be sent as an id. `currentUser` omits it
    /// so GitLab uses the token owner's own namespace.
    private nonisolated func namespaceID(for namespace: TargetNamespace) async throws -> Int? {
        let owner: String
        switch namespace {
        case .currentUser:
            return nil
        case .organization(let value), .adminForUser(let value):
            owner = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !owner.isEmpty else { return nil }

        let namespaces: [GitLabNamespaceDTO] = try await get(
            path: "/namespaces",
            query: [URLQueryItem(name: "search", value: owner)]
        )
        guard let match = namespaces.first(where: { $0.full_path.lowercased() == owner.lowercased() }) else {
            throw TargetProviderAPIError.validation(
                String(format: String.loc("No GitLab group or user namespace named %@ is visible to this token."), owner)
            )
        }
        return match.id
    }

    private nonisolated func existingProject(
        name: String,
        namespace: TargetNamespace
    ) async throws -> TargetCreateOutcome {
        let owner: String
        switch namespace {
        case .currentUser:
            let me: GitLabTargetUserDTO = try await get(path: "/user", query: [])
            owner = me.username
        case .organization(let value), .adminForUser(let value):
            owner = value
        }
        let lookup = try await fetchRepo(path: GitRemoteRepoPath(namespace: owner, name: name))
        switch lookup {
        case .found(let https, let ssh):
            return .alreadyExists(httpsCloneURL: https, sshCloneURL: ssh)
        case .missing:
            throw TargetProviderAPIError.validation(
                String.loc("GitLab reported the project path as taken, but it could not be read back.")
            )
        }
    }

    private nonisolated static func reportsExisting(_ message: String?) -> Bool {
        guard let message else { return false }
        let lower = message.lowercased()
        return lower.contains("has already been taken") || lower.contains("already exists")
    }

    private nonisolated static func encodedFullPath(_ path: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    // MARK: - HTTP helpers

    private nonisolated func post<Req: Encodable & Sendable, Resp: Decodable & Sendable>(
        path: String,
        body: Req
    ) async throws -> Resp {
        var req = makeRequest(path: path, query: [])
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw TargetProviderAPIError.decoding(error)
        }
        return try await send(req)
    }

    private nonisolated func get<Resp: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> Resp {
        try await send(makeRequest(path: path, query: query))
    }

    private nonisolated func makeRequest(path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(string: baseURL.absoluteString + path)
        if !query.isEmpty {
            components?.queryItems = query
        }
        var req = URLRequest(url: components?.url ?? baseURL)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        return req
    }

    private nonisolated func send<Resp: Decodable & Sendable>(_ req: URLRequest) async throws -> Resp {
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
        do {
            return try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw TargetProviderAPIError.decoding(error)
        }
    }

    private nonisolated static func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let message = Self.extractMessage(from: data)
            switch status {
            case 400, 422: throw TargetProviderAPIError.validation(message)
            case 401:      throw TargetProviderAPIError.unauthorized(message)
            case 403:      throw TargetProviderAPIError.forbidden(message)
            default:       throw TargetProviderAPIError.http(status: status, message: message)
            }
        }
    }

    /// GitLab returns `message` as a string for plain errors and as a field map
    /// for validation errors, so fall back to the raw body.
    private nonisolated static func extractMessage(from data: Data) -> String? {
        if let dto = try? JSONDecoder().decode(GitLabTargetErrorDTO.self, from: data) {
            if let m = dto.message, !m.isEmpty { return m }
            if let m = dto.error, !m.isEmpty { return m }
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return body.count > 200 ? String(body.prefix(200)) + "…" : body
        }
        return nil
    }
}

private nonisolated struct GitLabCreateProjectRequest: Encodable {
    let name: String
    let path: String
    let description: String?
    let visibility: String
    let namespace_id: Int?
    let initialize_with_readme: Bool
}

private nonisolated struct GitLabTargetProjectDTO: Decodable {
    let id: Int
    let path_with_namespace: String
    let http_url_to_repo: String
    let ssh_url_to_repo: String
}

private nonisolated struct GitLabNamespaceDTO: Decodable {
    let id: Int
    let full_path: String
}

private nonisolated struct GitLabTargetUserDTO: Decodable {
    let username: String
}

private nonisolated struct GitLabTargetTokenDTO: Decodable {
    let scopes: [String]
}

private nonisolated struct GitLabTargetErrorDTO: Decodable {
    let message: String?
    let error: String?
}
