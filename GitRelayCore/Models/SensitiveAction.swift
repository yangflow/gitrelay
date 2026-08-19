import Foundation

/// High-risk user actions that may require biometric authentication.
enum SensitiveAction: Equatable, Sendable {
    case revealToken
    case deleteRepository
    case changeTargetHost(originalURL: String, newURL: String)
}
