import Foundation

nonisolated struct MirrorStore {
    static func mirrorPath(for repoID: UUID) -> URL {
        Constants.mirrorsDirectory.appendingPathComponent(repoID.uuidString)
    }

    static func mirrorExists(for repoID: UUID) -> Bool {
        let headFile = mirrorPath(for: repoID).appendingPathComponent("HEAD")
        return FileManager.default.fileExists(atPath: headFile.path)
    }

    static func ensureBaseDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: Constants.mirrorsDirectory,
            withIntermediateDirectories: true
        )
    }

    static func deleteMirror(for repoID: UUID) throws {
        let path = mirrorPath(for: repoID)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
}
