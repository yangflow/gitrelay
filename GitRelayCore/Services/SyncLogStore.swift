import Foundation

struct PersistedSyncRecord: Codable, Equatable, Sendable {
    var startedAt: Date
    var finishedAt: Date?
    var succeeded: Bool
    var logLines: [String]

    init(record: SyncRecord) {
        startedAt = record.startedAt
        finishedAt = record.finishedAt
        succeeded = record.succeeded
        logLines = record.logLines
    }

    func tail(_ lineCount: Int?) -> [String] {
        guard let lineCount, lineCount >= 0 else { return logLines }
        guard logLines.count > lineCount else { return logLines }
        return Array(logLines.suffix(lineCount))
    }
}

enum SyncLogStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func logFile(for repoID: UUID) -> URL {
        logsDirectory.appendingPathComponent("\(repoID.uuidString).jsonl")
    }

    static var logsDirectory: URL {
        Constants.baseDirectory.appendingPathComponent("logs")
    }

    static func append(_ record: SyncRecord, for repoID: UUID) throws {
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let persisted = PersistedSyncRecord(record: record)
        let data = try encoder.encode(persisted)
        guard var line = String(data: data, encoding: .utf8) else {
            throw SyncLogStoreError.encodingFailed
        }
        line.append("\n")

        let url = logFile(for: repoID)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    static func loadRecords(for repoID: UUID) throws -> [PersistedSyncRecord] {
        let url = logFile(for: repoID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let contents = try String(contentsOf: url, encoding: .utf8)
        var records: [PersistedSyncRecord] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            if let record = try? decoder.decode(PersistedSyncRecord.self, from: data) {
                records.append(record)
            }
        }
        return records
    }

    static func latestRecord(for repoID: UUID) throws -> PersistedSyncRecord? {
        try loadRecords(for: repoID).last
    }

    static func formattedLogLines(for repoID: UUID, tail: Int?) throws -> [String] {
        guard let latest = try latestRecord(for: repoID) else { return [] }
        return latest.tail(tail)
    }
}

enum SyncLogStoreError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode sync log record."
        }
    }
}
