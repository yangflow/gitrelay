import Foundation

enum SyncPhase: Equatable {
    case fetchingSource
    case syncingTarget(String)
    case archivingTarget(String)

    var statusTitle: String {
        switch self {
        case .fetchingSource:
            return "正在更新本地镜像..."
        case .syncingTarget:
            return "正在同步..."
        case .archivingTarget:
            return "正在归档..."
        }
    }
}
