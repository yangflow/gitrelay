import Foundation

/// Pure policy for menu-bar accessory vs quit-on-last-window. No AppKit dependency so unit tests stay hermetic.
enum AppLifecyclePolicy {
    /// Closing the last titled window should switch to ``NSApplication.ActivationPolicy.accessory``.
    static func shouldSwitchToAccessoryAfterLastWindowCloses(keepInMenuBar: Bool) -> Bool {
        keepInMenuBar
    }

    /// ``NSApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed``.
    static func shouldTerminateAfterLastWindowClosed(keepInMenuBar: Bool) -> Bool {
        !keepInMenuBar
    }

    /// Whether any titled, still-visible window should block accessory / quit decisions.
    static func hasVisibleTitledWindow(_ windows: [(isTitled: Bool, isVisible: Bool)]) -> Bool {
        windows.contains { $0.isTitled && $0.isVisible }
    }
}
