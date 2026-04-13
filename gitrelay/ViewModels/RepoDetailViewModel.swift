import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class RepoDetailViewModel {
    var branches: [BranchInfo]  = []
    var isLoadingBranches       = false

    private let runner = GitRunner()

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
}
