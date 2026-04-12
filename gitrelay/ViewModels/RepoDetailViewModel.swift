import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class RepoDetailViewModel {
    var branches: [BranchInfo]  = []
    var isLoadingBranches       = false

    private let runner = GitRunner()

    func loadBranches(for repoID: UUID) {
        guard MirrorStore.mirrorExists(for: repoID) else {
            branches = []
            return
        }
        isLoadingBranches = true
        let path = MirrorStore.mirrorPath(for: repoID).path
        Task {
            let result        = (try? await runner.listRefs(repoPath: path)) ?? []
            branches          = result
            isLoadingBranches = false
        }
    }
}
