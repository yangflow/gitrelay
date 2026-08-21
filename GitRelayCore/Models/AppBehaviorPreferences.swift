import Foundation

/// User-adjustable preferences for login-item and menu-bar lifecycle behavior.
struct AppBehaviorPreferences: Equatable, Sendable {
    /// When enabled, closing the last titled window leaves the process running as a menu-bar accessory (Dock may hide).
    var keepInMenuBarWhenMainWindowCloses: Bool

    static let `default` = AppBehaviorPreferences(keepInMenuBarWhenMainWindowCloses: true)
}
