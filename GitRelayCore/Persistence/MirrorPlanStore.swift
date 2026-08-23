import Foundation

nonisolated struct MirrorPlanDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var mirrors: [MirrorPlan]

    init(version: Int = currentVersion, mirrors: [MirrorPlan]) {
        self.version = version
        self.mirrors = mirrors
    }
}

nonisolated struct MirrorPlanStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = Constants.mirrorPlansFile) {
        self.fileURL = fileURL
    }

    func load() throws -> [MirrorPlan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let document = try MirrorPersistenceCoding.decoder.decode(MirrorPlanDocument.self, from: data)
        guard document.version == MirrorPlanDocument.currentVersion else {
            throw MirrorPersistenceError.unsupportedVersion(document.version)
        }
        let validated = try document.mirrors.map {
            try $0.validated(allowMissingCredentials: true)
        }
        try Self.validateUniqueIDs(validated)
        return validated
    }

    func save(_ mirrors: [MirrorPlan]) throws {
        let validated = try mirrors.map {
            try $0.validated(allowMissingCredentials: true)
        }
        try Self.validateUniqueIDs(validated)
        let document = MirrorPlanDocument(mirrors: validated)
        let data = try MirrorPersistenceCoding.encoder.encode(document)
        try MirrorPersistenceCoding.atomicWrite(data, to: fileURL)
    }

    private static func validateUniqueIDs(_ mirrors: [MirrorPlan]) throws {
        var identifiers = Set<UUID>()
        for mirror in mirrors where !identifiers.insert(mirror.id).inserted {
            throw MirrorPersistenceError.duplicateMirrorID(mirror.id)
        }
    }
}

nonisolated enum MirrorPersistenceError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case duplicateMirrorID(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported GitRelay document version: \(version)."
        case .duplicateMirrorID(let mirrorID):
            "The GitRelay document contains duplicate mirror ID \(mirrorID.uuidString)."
        }
    }
}

nonisolated enum MirrorPersistenceCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let compactEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func atomicWrite(_ data: Data, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
