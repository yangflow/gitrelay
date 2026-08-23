import SwiftUI
import AppKit

@main
struct gitrelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel: GitRelayAppModel
    @State private var languageStore: AppLanguageStore

    private var workspace: WorkspaceModel { appModel.workspace }

    init() {
        #if DEBUG
        UITestBootstrap.prepareIfNeeded()
        #endif
        AppLanguageStore.bootstrapAppleLanguages()
        _appModel = State(initialValue: GitRelayAppModel())
        _languageStore = State(initialValue: AppLanguageStore())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appModel.library)
                .environment(appModel.operations)
                .environment(appModel.scheduling)
                .environment(appModel.management)
                .environment(workspace)
                .environment(appModel.issues)
                .environment(appModel.preferences)
                .environment(appModel.security)
                .environment(appModel.cache)
                .environment(appModel.webhooks)
                .environment(appModel.notifications)
                .environment(appModel.orgDiscovery)
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.preference)
                .environment(appModel.preferences.notificationStore)
                .environment(appModel.preferences.securityStore)
                .environment(appModel.preferences.cacheStore)
                .environment(appModel.preferences.behaviorStore)
                .environment(workspace.windowLayout)
                .environment(appModel.scheduling.environmentMonitor)
                .onOpenURL(perform: handleIncomingURL)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onAppear {
                    appDelegate.behaviorStore = appModel.preferences.behaviorStore
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    handleWindowWillClose()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: DesignTokens.Layout.windowDefaultWidth,
            height: DesignTokens.Layout.windowDefaultHeight
        )
        .commands {
            MainWindowCommands(
                workspace: workspace,
                operations: appModel.operations,
                notifications: appModel.notifications
            )
            SettingsCommands()
            AboutCommands()
        }

        Window(String.loc("Add Mirror"), id: "add-mirror") {
            MirrorEditorSheet(
                repo: nil,
                prefill: workspace.addMirrorPrefill,
                defaultPolicy: appModel.preferences.defaultPolicyStore.preferences,
                presentation: .window
            )
                .environment(appModel.library)
                .environment(appModel.operations)
                .environment(appModel.scheduling)
                .environment(appModel.management)
                .environment(workspace)
                .environment(appModel.issues)
                .environment(appModel.preferences)
                .environment(appModel.security)
                .environment(appModel.cache)
                .environment(appModel.webhooks)
                .environment(appModel.notifications)
                .environment(appModel.orgDiscovery)
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(workspace.addMirrorRequestID)
                .environment(appModel.preferences.notificationStore)
                .environment(appModel.preferences.securityStore)
                .environment(appModel.preferences.cacheStore)
                .environment(appModel.preferences.behaviorStore)
                .environment(workspace.windowLayout)
                .environment(appModel.scheduling.environmentMonitor)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: DesignTokens.Layout.addEditRepoSheetDefaultWidth,
            height: DesignTokens.Layout.addEditRepoSheetDefaultHeight
        )

        Window(String.loc("About GitRelay"), id: "about") {
            AboutView()
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.preference)
        }
        .windowResizability(.contentSize)

        Window(String.loc("Settings"), id: "settings") {
            SettingsView()
            .environment(appModel.library)
            .environment(appModel.operations)
            .environment(appModel.scheduling)
            .environment(appModel.management)
            .environment(appModel.cache)
            .environment(appModel.webhooks)
            .environment(workspace)
            .environment(appModel.preferences)
            .environment(appModel.security)
            .environment(appModel.orgDiscovery)
            .environment(appModel.preferences.notificationStore)
            .environment(appModel.preferences.securityStore)
            .environment(appModel.preferences.cacheStore)
            .environment(appModel.preferences.behaviorStore)
            .environment(appModel.scheduling.environmentMonitor)
            .environment(languageStore)
            .environment(\.locale, languageStore.locale)
            .onAppear {
                appDelegate.behaviorStore = appModel.preferences.behaviorStore
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: DesignTokens.Layout.settingsDefaultWidth,
            height: DesignTokens.Layout.settingsDefaultHeight
        )

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appModel.library)
                .environment(appModel.operations)
                .environment(appModel.scheduling)
                .environment(workspace)
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.preference)
                .environment(appModel.preferences.notificationStore)
                .environment(appModel.preferences.securityStore)
                .environment(appModel.preferences.behaviorStore)
                .environment(appModel.scheduling.environmentMonitor)
        } label: {
            MenuBarIconLabel(
                mirrors: appModel.library.mirrors,
                statuses: appModel.operations.statuses
            )
        }
        .menuBarExtraStyle(.window)
    }

    private func handleIncomingURL(_ url: URL) {
        if let repoID = WidgetDeepLink.repoID(from: url) {
            workspace.requestMirrorSelection(repoID)
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
            let keepInMenuBar = appModel.preferences.behaviorStore.preferences.keepInMenuBarWhenMainWindowCloses
            if AppLifecyclePolicy.shouldSwitchToAccessoryAfterLastWindowCloses(keepInMenuBar: keepInMenuBar) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
