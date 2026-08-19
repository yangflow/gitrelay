import Foundation

enum AppIntentBridgeError: LocalizedError, Equatable {
    case appNotReady
    case repoNotFound(String)

    var errorDescription: String? {
        switch self {
        case .appNotReady:
            return "GitRelay is not ready yet."
        case .repoNotFound(let name):
            return "No repository named \"\(name)\" was found."
        }
    }
}

@MainActor
enum AppIntentBridge {
    private(set) static weak var viewModel: AppViewModel?

    static func register(_ viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    static func triggerSync(repoName: String) throws {
        guard let viewModel else { throw AppIntentBridgeError.appNotReady }
        guard let repo = RepoIntentSupport.repo(matchingName: repoName, in: viewModel.repos) else {
            throw AppIntentBridgeError.repoNotFound(repoName)
        }
        viewModel.triggerSync(repoID: repo.id)
    }

    static func triggerSyncAll() throws {
        guard let viewModel else { throw AppIntentBridgeError.appNotReady }
        viewModel.triggerSyncAll()
    }

    static func syncStatusSnapshot(repoName: String) throws -> RepoSyncStatusSnapshot {
        guard let viewModel else { throw AppIntentBridgeError.appNotReady }
        guard let repo = RepoIntentSupport.repo(matchingName: repoName, in: viewModel.repos) else {
            throw AppIntentBridgeError.repoNotFound(repoName)
        }

        return RepoIntentSupport.makeSnapshot(
            repo: repo,
            runtimeStatus: viewModel.statuses[repo.id],
            isSyncInProgress: viewModel.inProgressSyncIDs.contains(repo.id)
        )
    }
}
