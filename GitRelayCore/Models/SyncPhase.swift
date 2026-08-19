import Foundation

enum SyncPhase: Equatable {
    case fetchingSource
    case syncingTarget(String)
    case archivingTarget(String)

    var statusTitle: String {
        switch self {
        case .fetchingSource:
            return "Updating local mirror..."
        case .syncingTarget:
            return "Syncing..."
        case .archivingTarget:
            return "Archiving..."
        }
    }
}
