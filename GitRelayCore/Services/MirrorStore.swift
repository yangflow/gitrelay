import Foundation

nonisolated struct MirrorStore {
    static func mirrorPath(for repoID: UUID) -> URL {
        mirrorPath(for: repoID, rootDirectory: Constants.mirrorCacheDirectory)
    }

    static func mirrorPath(
        for repoID: UUID,
        rootDirectory: URL
    ) -> URL {
        rootDirectory.appendingPathComponent(repoID.uuidString)
    }

    static func mirrorExists(for repoID: UUID) -> Bool {
        mirrorExists(for: repoID, rootDirectory: Constants.mirrorCacheDirectory)
    }

    static func mirrorExists(
        for repoID: UUID,
        rootDirectory: URL
    ) -> Bool {
        let headFile = mirrorPath(for: repoID, rootDirectory: rootDirectory)
            .appendingPathComponent("HEAD")
        return FileManager.default.fileExists(atPath: headFile.path)
    }

    static func ensureBaseDirectoryExists() throws {
        try ensureBaseDirectoryExists(at: Constants.mirrorCacheDirectory)
    }

    static func ensureBaseDirectoryExists(at rootDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    static func deleteMirror(for repoID: UUID) throws {
        try deleteMirror(for: repoID, rootDirectory: Constants.mirrorCacheDirectory)
    }

    static func deleteMirror(
        for repoID: UUID,
        rootDirectory: URL
    ) throws {
        let path = mirrorPath(for: repoID, rootDirectory: rootDirectory)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
}
