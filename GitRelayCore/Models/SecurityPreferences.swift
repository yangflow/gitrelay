import Foundation

/// User-adjustable security preferences for sensitive in-app actions.
struct SecurityPreferences: Equatable, Sendable {
    /// When enabled, high-risk actions require LocalAuthentication before proceeding.
    var requireBiometricForSensitive: Bool

    static let `default` = SecurityPreferences(requireBiometricForSensitive: true)
}
