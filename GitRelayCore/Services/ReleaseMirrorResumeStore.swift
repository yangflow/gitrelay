import Foundation

struct ReleaseMirrorResumeStore {
    static func resumeFile(repoID: UUID, targetID: UUID) -> URL {
        Constants.baseDirectory
            .appendingPathComponent("release-mirror")
            .appendingPathComponent(repoID.uuidString)
            .appendingPathComponent("\(targetID.uuidString).json")
    }

    static func statusFile(repoID: UUID) -> URL {
        Constants.baseDirectory
            .appendingPathComponent("release-mirror")
            .appendingPathComponent("\(repoID.uuidString)-status.json")
    }

    static func loadResume(repoID: UUID, targetID: UUID) -> ReleaseMirrorResumeState {
        let url = resumeFile(repoID: repoID, targetID: targetID)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ReleaseMirrorResumeState.self, from: data) else {
            return ReleaseMirrorResumeState()
        }
        return state
    }

    static func saveResume(_ state: ReleaseMirrorResumeState, repoID: UUID, targetID: UUID) throws {
        let url = resumeFile(repoID: repoID, targetID: targetID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    static func loadStatus(repoID: UUID) -> [ReleaseTargetMirrorStatus] {
        let url = statusFile(repoID: repoID)
        guard let data = try? Data(contentsOf: url),
              let statuses = try? JSONDecoder().decode([ReleaseTargetMirrorStatus].self, from: data) else {
            return []
        }
        return statuses
    }

    static func saveStatus(_ statuses: [ReleaseTargetMirrorStatus], repoID: UUID) throws {
        let url = statusFile(repoID: repoID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(statuses)
        try data.write(to: url, options: .atomic)
    }
}
