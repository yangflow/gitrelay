import SwiftUI
import AppKit

@main
struct gitrelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appVM)
                .environment(appVM.notificationPreferences)
                .environment(appVM.securityPreferences)
                .environment(appVM.appBehaviorPreferences)
                .environment(appVM.windowLayout)
                .environment(appVM.environmentMonitor)
                .onOpenURL(perform: handleIncomingURL)
                .onAppear {
                    appDelegate.behaviorStore = appVM.appBehaviorPreferences
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    handleWindowWillClose()
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            MainWindowCommands(appVM: appVM)
        }

        Window("About GitRelay", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Settings {
            TabView {
                SettingsView()
                    .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                OrgSubscriptionSettingsView()
                    .tabItem { Label(String(localized: "Subscribe"), systemImage: "building.2") }
                VerificationSettingsView()
                    .tabItem { Label("Verify", systemImage: "checkmark.shield") }
            }
            .environment(appVM.notificationPreferences)
            .environment(appVM.securityPreferences)
            .environment(appVM.cachePreferences)
            .environment(appVM.appBehaviorPreferences)
            .environment(appVM.environmentMonitor)
            .environment(appVM)
            .onAppear {
                appDelegate.behaviorStore = appVM.appBehaviorPreferences
            }
        }

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appVM)
                .environment(appVM.notificationPreferences)
                .environment(appVM.securityPreferences)
                .environment(appVM.appBehaviorPreferences)
                .environment(appVM.environmentMonitor)
        } label: {
            MenuBarIconLabel(appVM: appVM)
        }
        .menuBarExtraStyle(.window)
    }

    private func handleIncomingURL(_ url: URL) {
        if let repoID = WidgetDeepLink.repoID(from: url) {
            appVM.pendingMainWindowRepoID = repoID
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .gitrelayOpenMainWindow, object: nil)
    }

    private func handleWindowWillClose() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            let windowStates = NSApp.windows.map {
                (isTitled: $0.styleMask.contains(.titled), isVisible: $0.isVisible)
            }
            guard !AppLifecyclePolicy.hasVisibleTitledWindow(windowStates) else { return }
            let keepInMenuBar = appVM.appBehaviorPreferences.preferences.keepInMenuBarWhenMainWindowCloses
            if AppLifecyclePolicy.shouldSwitchToAccessoryAfterLastWindowCloses(keepInMenuBar: keepInMenuBar) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
