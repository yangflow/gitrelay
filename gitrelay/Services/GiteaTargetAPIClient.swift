import CryptoKit
import Foundation

struct GiteaTargetAPIClient: TargetProviderAPIClient {
    nonisolated let provider: GitProvider = .gitea
    nonisolated let baseURL: URL
    nonisolated let token: String
    private nonisolated let session: URLSession = .shared

    nonisolated init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    nonisolated func fetchTokenScopes() async throws -> Set<String> {
        let me: GiteaUserDTO = try await get(path: "/user")
        let encodedLogin = me.login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? me.login
        let tokens: [GiteaAccessTokenDTO] = try await get(path: "/users/\(encodedLogin)/tokens")
        let tokenHash = Self.sha1Hex(token)
        if let match = tokens.first(where: { $0.sha1.lowercased() == tokenHash.lowercased() }) {
            return ProviderTokenScope.parseGiteaTokenScopes(match.scopes)
        }
        return []
    }

    nonisolated func fetchRepo(path: GitRemoteRepoPath) async throws -> TargetRepoLookup {
        // A URL without an owner segment means the token's own account.
        var owner = path.namespace
        if owner.isEmpty {
            let me: GiteaUserDTO = try await get(path: "/user")
            owner = me.login
        }
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedName = path.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path.name
        do {
            let dto: GiteaRepoDTO = try await get(path: "/repos/\(encodedOwner)/\(encodedName)")
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
        let path: String
        switch namespace {
        case .currentUser:
            path = "/user/repos"
        case .organization(let org):
            let encoded = org.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? org
            path = "/orgs/\(encoded)/repos"
        case .adminForUser(let user):
            let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
            path = "/admin/users/\(encoded)/repos"
        }

        let body = GiteaCreateRepoRequest(
            name: name,
            description: description,
            private: isPrivate,
            auto_init: false,
            default_branch: "main"
        )

        do {
            let dto: GiteaRepoDTO = try await post(path: path, body: body)
            return .created(httpsCloneURL: dto.clone_url, sshCloneURL: dto.ssh_url)
        } catch TargetProviderAPIError.http(status: 409, message: _) {
            return try await fetchExistingRepoURLs(name: name, namespace: namespace)
        }
    }

    private nonisolated func fetchExistingRepoURLs(name: String, namespace: TargetNamespace) async throws -> TargetCreateOutcome {
        let owner: String
        switch namespace {
        case .currentUser:
            let me: GiteaUserDTO = try await get(path: "/user")
            owner = me.login
        case .organization(let org):
            owner = org
        case .adminForUser(let user):
            owner = user
        }
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let dto: GiteaRepoDTO = try await get(path: "/repos/\(encodedOwner)/\(encodedName)")
        return .alreadyExists(httpsCloneURL: dto.clone_url, sshCloneURL: dto.ssh_url)
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
        return try await send(req)
    }

    private nonisolated func get<Resp: Decodable & Sendable>(path: String) async throws -> Resp {
        let req = makeRequest(path: path)
        return try await send(req)
    }

    private nonisolated func makeRequest(path: String) -> URLRequest {
        let url = URL(string: baseURL.absoluteString + path)!
        var req = URLRequest(url: url)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
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

    private nonisolated static func sha1Hex(_ value: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let message = Self.extractMessage(from: data)
            switch status {
            case 401: throw TargetProviderAPIError.unauthorized(message)
            case 403: throw TargetProviderAPIError.forbidden(message)
            case 409: throw TargetProviderAPIError.http(status: 409, message: message)
            case 422: throw TargetProviderAPIError.validation(message)
            default:  throw TargetProviderAPIError.http(status: status, message: message)
            }
        }
    }

    private nonisolated static func extractMessage(from data: Data) -> String? {
        if let dto = try? JSONDecoder().decode(GiteaErrorDTO.self, from: data) {
            if let m = dto.message, !m.isEmpty { return m }
            if let m = dto.error, !m.isEmpty { return m }
            if let m = dto.url, !m.isEmpty { return m }
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return body.count > 200 ? String(body.prefix(200)) + "…" : body
        }
        return nil
    }
}

private nonisolated struct GiteaCreateRepoRequest: Encodable {
    let name: String
    let description: String?
    let `private`: Bool
    let auto_init: Bool
    let default_branch: String?
}

private nonisolated struct GiteaRepoDTO: Decodable {
    let id: Int
    let name: String
    let full_name: String
    let clone_url: String
    let ssh_url: String
}

private nonisolated struct GiteaAccessTokenDTO: Decodable {
    let sha1: String
    let scopes: [String]
}

private nonisolated struct GiteaUserDTO: Decodable {
    let id: Int
    let login: String
}

private nonisolated struct GiteaErrorDTO: Decodable {
    let message: String?
    let error: String?
    let url: String?
}
