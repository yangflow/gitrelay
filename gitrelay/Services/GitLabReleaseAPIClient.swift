import Foundation

struct GitLabReleaseAPIClient: ReleaseProviderClient {
    nonisolated let provider: GitProvider = .gitlab
    nonisolated let token: String
    nonisolated let baseURL: URL
    private nonisolated let session: URLSession = .shared

    nonisolated init(token: String, baseURL: URL? = nil) {
        self.token = token
        self.baseURL = baseURL ?? GitProvider.gitlab.apiBaseURL
    }

    nonisolated func listReleases(ownerRepo: String) async throws -> [ReleaseInfo] {
        var page = 1
        let perPage = 100
        var all: [ReleaseInfo] = []

        while true {
            let endpoint = ReleaseProviderEndpoints.gitlabListReleases(
                projectPath: ownerRepo,
                page: page,
                perPage: perPage
            )
            let dtos: [GitLabReleaseDTO] = try await request(path: endpoint.path, query: endpoint.query)
            all.append(contentsOf: dtos.map(Self.toDomain))
            if dtos.count < perPage { break }
            page += 1
        }

        return all
    }

    nonisolated func createRelease(ownerRepo: String, release: ReleaseInfo) async throws -> String {
        let body = GitLabCreateReleaseBody(
            tag_name: release.tagName,
            name: release.title,
            description: release.body
        )
        _ = try await request(
            path: ReleaseProviderEndpoints.gitlabCreateRelease(projectPath: ownerRepo),
            query: [],
            method: "POST",
            body: body
        ) as GitLabReleaseDTO
        return release.tagName
    }

    nonisolated func fetchReleaseUploadURL(ownerRepo: String, tagName: String) async throws -> String? {
        nil
    }

    nonisolated func uploadAsset(
        ownerRepo: String,
        tagName: String,
        releaseUploadURL: String?,
        asset: ReleaseAssetInfo,
        data: Data
    ) async throws {
        let uploaded: GitLabUploadDTO = try await uploadFile(projectPath: ownerRepo, fileName: asset.name, data: data)
        let linkBody = GitLabAssetLinkBody(name: asset.name, url: uploaded.full_path)
        _ = try await request(
            path: ReleaseProviderEndpoints.gitlabCreateAssetLink(projectPath: ownerRepo, tagName: tagName),
            query: [],
            method: "POST",
            body: linkBody
        ) as GitLabAssetLinkDTO
    }

    // MARK: - Private

    private nonisolated func uploadFile(projectPath: String, fileName: String, data: Data) async throws -> GitLabUploadDTO {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let path = ReleaseProviderEndpoints.gitlabUploadFile(projectPath: projectPath)
        let components = URLComponents(string: baseURL.absoluteString + path)!
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        req.httpBody = body

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

        do {
            return try JSONDecoder().decode(GitLabUploadDTO.self, from: responseData)
        } catch {
            throw ProviderAPIError.decoding(error)
        }
    }

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
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
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
        return nil
    }

    private nonisolated static func toDomain(_ dto: GitLabReleaseDTO) -> ReleaseInfo {
        let assets = dto.assets?.links?.map {
            ReleaseAssetInfo(
                name: $0.name,
                downloadURL: URL(string: $0.url)!,
                size: nil,
                contentType: nil
            )
        } ?? []
        return ReleaseInfo(
            tagName: dto.tag_name,
            title: dto.name,
            body: dto.description ?? "",
            assets: assets
        )
    }
}

private nonisolated struct GitLabReleaseDTO: Decodable {
    let tag_name: String
    let name: String
    let description: String?
    let assets: GitLabReleaseAssetsDTO?
}

private nonisolated struct GitLabReleaseAssetsDTO: Decodable {
    let links: [GitLabReleaseAssetLinkDTO]?
}

private nonisolated struct GitLabReleaseAssetLinkDTO: Decodable {
    let name: String
    let url: String
}

private nonisolated struct GitLabCreateReleaseBody: Encodable {
    let tag_name: String
    let name: String
    let description: String
}

private nonisolated struct GitLabAssetLinkBody: Encodable {
    let name: String
    let url: String
    let link_type: String = "other"
}

private nonisolated struct GitLabAssetLinkDTO: Decodable {
    let name: String
    let url: String
}

private nonisolated struct GitLabUploadDTO: Decodable {
    let full_path: String
}

private nonisolated struct GitLabErrorDTO: Decodable {
    let message: String?
    let error: String?
    let error_description: String?
}
