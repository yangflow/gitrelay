import Foundation

/// The three locked steps of the browse-remote wizard.
///
/// Deliberately closed at three: connect, pick, configure. Creating the target
/// repositories and reviewing the outcome are the tail of step 3, not steps of
/// their own, so the rail never grows past 3.
nonisolated enum BrowseRemoteStep: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case connect = 1
    case select = 2
    case configure = 3

    var id: Int { rawValue }

    static let total = BrowseRemoteStep.allCases.count

    var number: Int { rawValue }

    var isFirst: Bool { self == .connect }

    var title: String {
        switch self {
        case .connect:
            String(localized: "Choose a Host")
        case .select:
            String(localized: "Pick Repositories")
        case .configure:
            String(localized: "Configure the Target")
        }
    }

    var subtitle: String {
        switch self {
        case .connect:
            String(localized: "Choose the Git host and account to browse.")
        case .select:
            String(localized: "Select the repositories you want to mirror.")
        case .configure:
            String(localized: "Choose where the mirrors live and how they authenticate.")
        }
    }

    var progressLabel: String {
        String(localized: "Step \(number) of \(BrowseRemoteStep.total)")
    }
}

/// Wizard state of ``BrowseRemoteRepoViewModel``.
///
/// Lives in GitRelayCore so the step rail and the Back button can be exercised
/// without SwiftUI or a live view model.
nonisolated enum BrowseRemotePhase: Hashable, Sendable {
    case connect
    case selecting
    case configureTarget
    case submitting
    case result

    var step: BrowseRemoteStep {
        switch self {
        case .connect:
            .connect
        case .selecting:
            .select
        case .configureTarget, .submitting, .result:
            .configure
        }
    }

    /// Phase the Back button returns to, or nil where Back is not offered
    /// (step 1, and the terminal submitting / result phases).
    var previous: BrowseRemotePhase? {
        switch self {
        case .selecting:
            .connect
        case .configureTarget:
            .selecting
        case .connect, .submitting, .result:
            nil
        }
    }

    var canGoBack: Bool { previous != nil }
}
