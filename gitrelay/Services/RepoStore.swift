import Foundation

struct RepoStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() throws -> [RepoConfig] {
        let url = Constants.reposFile
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([RepoConfig].self, from: data)
    }

    static func save(_ repos: [RepoConfig]) throws {
        let data = try encoder.encode(repos)
        let tmp = Constants.reposFile.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(Constants.reposFile, withItemAt: tmp)
    }
}
