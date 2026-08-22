import Foundation

/// Grouping headers of the main-window sidebar.
nonisolated enum MainSidebarSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case accounts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            String.loc("Overview")
        case .accounts:
            String.loc("Accounts")
        case .settings:
            String.loc("Settings")
        }
    }

    var items: [MainSidebarItem] {
        MainSidebarItem.allCases.filter { $0.section == self }
    }
}

/// The only destinations the main-window sidebar offers.
///
/// Deliberately closed: adding a case here is a product decision, not a
/// refactor. Home / Favorites / Labels / Templates are not part of the set.
nonisolated enum MainSidebarItem: String, CaseIterable, Identifiable, Hashable, Sendable {
    case repositories
    case queue
    case browseRemote
    case githubAccounts
    case gitlabAccounts
    case giteaAccounts
    case settings

    var id: String { rawValue }

    static let `default` = MainSidebarItem.repositories

    var section: MainSidebarSection {
        switch self {
        case .repositories, .queue, .browseRemote:
            .overview
        case .githubAccounts, .gitlabAccounts, .giteaAccounts:
            .accounts
        case .settings:
            .settings
        }
    }

    var title: String {
        switch self {
        case .repositories:
            String.loc("Repositories")
        case .queue:
            String.loc("Queue")
        case .browseRemote:
            String.loc("Browse Remote")
        case .githubAccounts:
            GitProvider.github.displayName
        case .gitlabAccounts:
            GitProvider.gitlab.displayName
        case .giteaAccounts:
            GitProvider.gitea.displayName
        case .settings:
            String.loc("Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .repositories:
            "tray.full"
        case .queue:
            "list.bullet"
        case .browseRemote:
            "globe"
        case .githubAccounts:
            GitProvider.github.symbolName
        case .gitlabAccounts:
            GitProvider.gitlab.symbolName
        case .giteaAccounts:
            GitProvider.gitea.symbolName
        case .settings:
            "gearshape"
        }
    }

    /// Provider whose accounts this row scopes the 安全 list to, when the row is
    /// an account row.
    var provider: GitProvider? {
        switch self {
        case .githubAccounts:
            .github
        case .gitlabAccounts:
            .gitlab
        case .giteaAccounts:
            .gitea
        default:
            nil
        }
    }

    /// The sidebar row that opens the dedicated account page for one provider.
    static func accountsItem(for provider: GitProvider?) -> MainSidebarItem? {
        guard let provider else { return nil }
        switch provider {
        case .github:
            return .githubAccounts
        case .gitlab:
            return .gitlabAccounts
        case .gitea:
            return .giteaAccounts
        }
    }
}
