import Foundation

enum MirrorWidgetStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case syncing
    case queued
    case diverged
    case unknown
}
