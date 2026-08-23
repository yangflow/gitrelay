import Foundation
import Darwin

nonisolated struct MirrorStateDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var snapshots: [MirrorHealthSnapshot]

    init(version: Int = currentVersion, snapshots: [MirrorHealthSnapshot]) {
        self.version = version
        self.snapshots = snapshots
    }
}

nonisolated struct MirrorStateStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = Constants.mirrorStateFile) {
        self.fileURL = fileURL
    }

    func load() throws -> [UUID: MirrorHealthSnapshot] {
        try withExclusiveFileLock {
            try loadUnlocked()
        }
    }

    func save(_ snapshots: [UUID: MirrorHealthSnapshot]) throws {
        try withExclusiveFileLock {
            try saveUnlocked(snapshots)
        }
    }

    /// Atomically reloads and replaces one mirror's compact health record.
    /// The sidecar lock is process-wide and cross-process, so concurrent app,
    /// widget, intent, and CLI writers cannot overwrite unrelated mirrors.
    @discardableResult
    func update(
        mirrorID: UUID,
        _ transform: (MirrorHealthSnapshot?) throws -> MirrorHealthSnapshot
    ) throws -> MirrorHealthSnapshot {
        try withExclusiveFileLock {
            var snapshots = try loadUnlocked()
            let next = try transform(snapshots[mirrorID])
            snapshots[mirrorID] = next
            try saveUnlocked(snapshots)
            return next
        }
    }

    private func loadUnlocked() throws -> [UUID: MirrorHealthSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        let document = try MirrorPersistenceCoding.decoder.decode(MirrorStateDocument.self, from: data)
        guard document.version == MirrorStateDocument.currentVersion else {
            throw MirrorPersistenceError.unsupportedVersion(document.version)
        }
        var snapshots: [UUID: MirrorHealthSnapshot] = [:]
        for snapshot in document.snapshots {
            guard snapshots.updateValue(snapshot, forKey: snapshot.mirrorID) == nil else {
                throw MirrorPersistenceError.duplicateMirrorID(snapshot.mirrorID)
            }
        }
        return snapshots
    }

    private func saveUnlocked(_ snapshots: [UUID: MirrorHealthSnapshot]) throws {
        let ordered = snapshots.values.sorted { $0.mirrorID.uuidString < $1.mirrorID.uuidString }
        let document = MirrorStateDocument(snapshots: ordered)
        let data = try MirrorPersistenceCoding.encoder.encode(document)
        try MirrorPersistenceCoding.atomicWrite(data, to: fileURL)
    }

    private func withExclusiveFileLock<T>(_ body: () throws -> T) throws -> T {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = fileURL.appendingPathExtension("lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}
