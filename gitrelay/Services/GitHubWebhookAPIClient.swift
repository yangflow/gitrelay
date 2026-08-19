import Foundation

/// Optional GitHub webhook registration via the Repos Hooks API.
struct GitHubWebhookAPIClient {
    nonisolated let token: String
    private nonisolated let session: URLSession

    nonisolated init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Creates a push webhook. Requires `admin:repo_hook` (disclosed in UI).
    nonisolated func createPushHook(
        owner: String,
        repo: String,
        hookURL: String,
        secret: String
    ) async throws -> GitHubWebhookRegistration {
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let path = "/repos/\(encodedOwner)/\(encodedRepo)/hooks"
        let body = GitHubCreateHookRequest(
            name: "web",
            active: true,
            events: ["push"],
            config: GitHubHookConfig(
                url: hookURL,
                content_type: "json",
                secret: secret,
                insecure_ssl: "0"
            )
        )
        let dto: GitHubHookDTO = try await post(path: path, body: body)
        return GitHubWebhookRegistration(id: dto.id, url: dto.config?.url ?? hookURL)
    }

    nonisolated func fetchTokenScopes() async throws -> Set<String> {
        let (_, response) = try await rawRequest(path: "/user", method: "GET", body: Optional<Data>.none)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderAPIError.http(status: -1, message: nil)
        }
        return ProviderTokenScope.parseGitHubOAuthScopesHeader(http.value(forHTTPHeaderField: "X-OAuth-Scopes"))
    }

    private nonisolated func post<Req: Encodable & Sendable, Resp: Decodable & Sendable>(
        path: String,
        body: Req
    ) async throws -> Resp {
        let data = try JSONEncoder().encode(body)
        let (responseData, _) = try await rawRequest(path: path, method: "POST", body: data)
        do {
            return try JSONDecoder().decode(Resp.self, from: responseData)
        } catch {
            throw ProviderAPIError.decoding(error)
        }
    }

    private nonisolated func rawRequest(
        path: String,
        method: String,
        body: Data?
    ) async throws -> (Data, URLResponse) {
        let url = URL(string: GitProvider.github.apiBaseURL.absoluteString + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderAPIError.http(status: -1, message: nil)
            }
            try Self.validate(status: http.statusCode, data: data)
            return (data, response)
        } catch let error as ProviderAPIError {
            throw error
        } catch {
            throw ProviderAPIError.network(error)
        }
    }

    private nonisolated static func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(GitHubHookErrorDTO.self, from: data))?.message
            switch status {
            case 401: throw ProviderAPIError.unauthorized(message)
            case 403: throw ProviderAPIError.forbidden(message)
            case 404: throw ProviderAPIError.notFound(message)
            case 422: throw ProviderAPIError.http(status: 422, message: message)
            default:  throw ProviderAPIError.http(status: status, message: message)
            }
        }
    }
}

nonisolated struct GitHubWebhookRegistration: Equatable, Sendable {
    let id: Int
    let url: String
}

private nonisolated struct GitHubCreateHookRequest: Encodable, Sendable {
    let name: String
    let active: Bool
    let events: [String]
    let config: GitHubHookConfig
}

private nonisolated struct GitHubHookConfig: Codable, Sendable {
    let url: String
    let content_type: String
    let secret: String?
    let insecure_ssl: String
}

private nonisolated struct GitHubHookDTO: Decodable, Sendable {
    let id: Int
    let config: GitHubHookConfigDTO?
}

private nonisolated struct GitHubHookConfigDTO: Decodable, Sendable {
    let url: String?
}

private nonisolated struct GitHubHookErrorDTO: Decodable {
    let message: String?
}
