import Foundation

/// Internal navigation state for choosing mirror sources from a connected service.
nonisolated enum ConnectedServiceSourcePhase: Hashable, Sendable {
    case connect
    case selecting
    case configureTarget
    case submitting
    case result

    var previous: ConnectedServiceSourcePhase? {
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
