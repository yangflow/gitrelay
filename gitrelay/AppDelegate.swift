import AppKit

/// Handles quit-on-last-window vs menu-bar accessory based on ``AppBehaviorPreferences``.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var behaviorStore: AppBehaviorPreferencesStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let keepInMenuBar = behaviorStore?.preferences.keepInMenuBarWhenMainWindowCloses ?? true
        return AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(keepInMenuBar: keepInMenuBar)
    }
}
