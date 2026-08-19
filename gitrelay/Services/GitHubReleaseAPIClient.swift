import Foundation

struct GitHubReleaseAPIClient: ReleaseProviderClient {
    nonisolated let provider: GitProvider = .github
    nonisolated let token: String
    nonisolated let baseURL: URL
    private nonisolated let session: URLSession = .shared

    nonisolated init(token: String, baseURL: URL? = nil) {
        self.token = token
        self.baseURL = baseURL ?? GitProvider.github.apiBaseURL
    }

    nonisolated func listReleases(ownerRepo: String) async throws -> [ReleaseInfo] {
        var page = 1
        let perPage = 100
        var all: [ReleaseInfo] = []

        while true {
            let endpoint = ReleaseProviderEndpoints.githubListReleases(
                ownerRepo: ownerRepo,
                page: page,
                perPage: perPage
            )
            let dtos: [GitHubReleaseDTO] = try await request(path: endpoint.path, query: endpoint.query)
            all.append(contentsOf: dtos.map(Self.toDomain))
            if dtos.count < perPage { break }
            page += 1
        }

        return all
    }

    nonisolated func createRelease(ownerRepo: String, release: ReleaseInfo) async throws -> String {
        let body = GitHubCreateReleaseBody(
            tag_name: release.tagName,
            name: release.title,
            body: release.body,
            draft: false,
            prerelease: false
        )
        do {
            let dto: GitHubReleaseDTO = try await request(
                path: ReleaseProviderEndpoints.githubCreateRelease(ownerRepo: ownerRepo),
                query: [],
                method: "POST",
                body: body
            )
            return dto.upload_url ?? ""
        } catch ProviderAPIError.http(status: 422, _) {
            return try await fetchReleaseUploadURL(ownerRepo: ownerRepo, tagName: release.tagName) ?? ""
        }
    }

    nonisolated func fetchReleaseUploadURL(ownerRepo: String, tagName: String) async throws -> String? {
        let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName
        let dto: GitHubReleaseDTO = try await request(
            path: "/repos/\(ownerRepo)/releases/tags/\(encodedTag)",
            query: []
        )
        return dto.upload_url
    }

    nonisolated func uploadAsset(
        ownerRepo: String,
        tagName: String,
        releaseUploadURL: String?,
        asset: ReleaseAssetInfo,
        data: Data
    ) async throws {
        guard let uploadTemplate = releaseUploadURL.flatMap({ URL(string: $0) }),
              let uploadURL = ReleaseProviderEndpoints.githubAssetUploadURL(
                from: uploadTemplate,
                fileName: asset.name
              ) else {
            throw ReleaseMirrorError.assetUploadFailed(asset.name)
        }

        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(asset.contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        req.httpBody = data

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: req)
        } catch {
            throw ProviderAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderAPIError.http(status: -1, message: nil)
        }
        try Self.validate(status: http.statusCode, data: responseData)
    }

    // MARK: - Private

    private nonisolated func request<T: Decodable & Sendable, B: Encodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        method: String = "GET",
        body: B? = nil
    ) async throws -> T {
        let (data, _) = try await rawRequest(path: path, query: query, method: method, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(error)
        }
    }

    private nonisolated func request<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> T {
        try await request(path: path, query: query, method: "GET", body: Optional<String>.none)
    }

    private nonisolated func rawRequest<B: Encodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: B?
    ) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: baseURL.absoluteString + path)!
        components.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }

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
            case 422 where message?.contains("already_exists") == true:
                throw ProviderAPIError.http(status: status, message: message)
            default:  throw ProviderAPIError.http(status: status, message: message)
            }
        }
    }

    private nonisolated static func toDomain(_ dto: GitHubReleaseDTO) -> ReleaseInfo {
        ReleaseInfo(
            tagName: dto.tag_name,
            title: dto.name ?? dto.tag_name,
            body: dto.body ?? "",
            assets: dto.assets.map {
                ReleaseAssetInfo(
                    name: $0.name,
                    downloadURL: URL(string: $0.browser_download_url)!,
                    size: $0.size,
                    contentType: $0.content_type
                )
            }
        )
    }
}

private nonisolated struct GitHubReleaseDTO: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let upload_url: String?
    let assets: [GitHubReleaseAssetDTO]
}

private nonisolated struct GitHubReleaseAssetDTO: Decodable {
    let name: String
    let browser_download_url: String
    let size: Int?
    let content_type: String?
}

private nonisolated struct GitHubCreateReleaseBody: Encodable {
    let tag_name: String
    let name: String
    let body: String
    let draft: Bool
    let prerelease: Bool
}

private nonisolated struct GitHubErrorDTO: Decodable {
    let message: String?
}
