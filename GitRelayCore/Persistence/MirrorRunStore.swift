import Foundation

nonisolated struct MirrorRunStore: Sendable {
    let directoryURL: URL

    init(directoryURL: URL = Constants.mirrorLogsDirectory) {
        self.directoryURL = directoryURL
    }

    func fileURL(for mirrorID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(mirrorID.uuidString.lowercased()).jsonl")
    }

    func append(_ record: MirrorRunRecord) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let safeRecord = redacted(record)
        // JSON Lines requires every record to occupy exactly one physical line.
        let data = try MirrorPersistenceCoding.compactEncoder.encode(safeRecord)
        guard var line = String(data: data, encoding: .utf8) else {
            throw MirrorRunStoreError.encodingFailed
        }
        line.append("\n")

        let url = fileURL(for: record.mirrorID)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    func load(mirrorID: UUID) throws -> [MirrorRunRecord] {
        let url = fileURL(for: mirrorID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                try MirrorPersistenceCoding.decoder.decode(
                    MirrorRunRecord.self,
                    from: Data(line.utf8)
                )
            }
    }

    private func redacted(_ record: MirrorRunRecord) -> MirrorRunRecord {
        var safe = record
        safe.logLines = record.logLines.map(CredentialRedactor.redact)
        if var failure = record.failure {
            failure.message = CredentialRedactor.redact(failure.message)
            safe.failure = failure
        }
        safe.destinationResults = record.destinationResults.map { result in
            var result = result
            if var failure = result.failure {
                failure.message = CredentialRedactor.redact(failure.message)
                result.failure = failure
            }
            return result
        }
        safe.verificationResults = record.verificationResults.map { result in
            var result = result
            if var failure = result.failure {
                failure.message = CredentialRedactor.redact(failure.message)
                result.failure = failure
            }
            if case .diverged(let message) = result.integrity {
                result.integrity = .diverged(CredentialRedactor.redact(message))
            } else if case .inconclusive(let message) = result.integrity {
                result.integrity = .inconclusive(CredentialRedactor.redact(message))
            }
            return result
        }
        return safe
    }
}

nonisolated enum MirrorRunStoreError: Error, Equatable, LocalizedError, Sendable {
    case encodingFailed

    var errorDescription: String? {
        "Failed to encode the mirror run record."
    }
}
