import Foundation

enum SyncStatus: Equatable {
    case unknown
    case idle
    case ahead(Int)
    case syncing
    case failed(String)
}
