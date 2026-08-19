import Foundation

enum SyncPhase: Equatable {
    case fetchingSource
    case syncingTarget(String)
    case archivingTarget(String)

    var statusTitle: String {
        switch self {
        case .fetchingSource:
            return String(localized: "Updating local mirror...")
        case .syncingTarget:
            return String(localized: "Syncing...")
        case .archivingTarget:
            return String(localized: "Archiving...")
        }
    }
}
