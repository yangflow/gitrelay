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
            String(localized: "Overview")
        case .accounts:
            String(localized: "Accounts")
        case .settings:
            String(localized: "Settings")
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
    case settings

    var id: String { rawValue }

    static let `default` = MainSidebarItem.repositories

    var section: MainSidebarSection {
        switch self {
        case .repositories, .queue, .browseRemote:
            .overview
        case .githubAccounts, .gitlabAccounts:
            .accounts
        case .settings:
            .settings
        }
    }

    var title: String {
        switch self {
        case .repositories:
            String(localized: "Repositories")
        case .queue:
            String(localized: "Queue")
        case .browseRemote:
            String(localized: "Browse Remote")
        case .githubAccounts:
            GitProvider.github.displayName
        case .gitlabAccounts:
            GitProvider.gitlab.displayName
        case .settings:
            String(localized: "Settings")
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
        case .settings:
            "gearshape"
        }
    }

    /// Provider whose accounts this row lists, when the row is an account row.
    var provider: GitProvider? {
        switch self {
        case .githubAccounts:
            .github
        case .gitlabAccounts:
            .gitlab
        default:
            nil
        }
    }
}
