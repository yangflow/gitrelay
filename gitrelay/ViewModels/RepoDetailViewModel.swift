import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class RepoDetailViewModel {
    var branches: [BranchInfo]  = []
    var isLoadingBranches       = false
    var releaseStatuses: [ReleaseTargetMirrorStatus] = []

    private let runner = GitRunner()
    private let releaseMirrorService = ReleaseMirrorService()

    func loadBranches(for repoID: UUID) async {
        guard MirrorStore.mirrorExists(for: repoID) else {
            branches = []
            return
        }
        isLoadingBranches = true
        defer { isLoadingBranches = false }
        let path = MirrorStore.mirrorPath(for: repoID).path
        branches = (try? await runner.listRefs(repoPath: path)) ?? []
    }

    func loadReleaseStatus(for repo: RepoConfig) async {
        releaseStatuses = releaseMirrorService.loadStatus(repo: repo)
    }
}
