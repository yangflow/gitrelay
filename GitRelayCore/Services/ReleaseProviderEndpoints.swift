import Foundation

enum ReleaseProviderEndpoints {
    nonisolated static func githubListReleases(ownerRepo: String, page: Int, perPage: Int) -> (path: String, query: [URLQueryItem]) {
        (
            path: "/repos/\(ownerRepo)/releases",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
    }

    nonisolated static func githubCreateRelease(ownerRepo: String) -> String {
        "/repos/\(ownerRepo)/releases"
    }

    nonisolated static func githubUploadAsset(ownerRepo: String, releaseID: Int, fileName: String) -> (path: String, query: [URLQueryItem]) {
        (
            path: "/repos/\(ownerRepo)/releases/\(releaseID)/assets",
            query: [URLQueryItem(name: "name", value: fileName)]
        )
    }

    /// GitHub asset upload uses the absolute `upload_url` returned by the create-release API.
    nonisolated static func githubAssetUploadURL(from uploadURLTemplate: URL, fileName: String) -> URL? {
        var components = URLComponents(url: uploadURLTemplate, resolvingAgainstBaseURL: false)
        var query = components?.queryItems ?? []
        query.removeAll { $0.name == "name" }
        query.append(URLQueryItem(name: "name", value: fileName))
        components?.queryItems = query
        return components?.url
    }

    nonisolated static func gitlabListReleases(projectPath: String, page: Int, perPage: Int) -> (path: String, query: [URLQueryItem]) {
        (
            path: "/projects/\(gitlabEncodedPath(projectPath))/releases",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
    }

    nonisolated static func gitlabCreateRelease(projectPath: String) -> String {
        "/projects/\(gitlabEncodedPath(projectPath))/releases"
    }

    nonisolated static func gitlabUploadFile(projectPath: String) -> String {
        "/projects/\(gitlabEncodedPath(projectPath))/uploads"
    }

    nonisolated static func gitlabCreateAssetLink(projectPath: String, tagName: String) -> String {
        "/projects/\(gitlabEncodedPath(projectPath))/releases/\(gitlabEncodedPath(tagName))/assets/links"
    }

    nonisolated static func gitlabEncodedPath(_ path: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

}
