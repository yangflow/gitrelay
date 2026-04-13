import SwiftUI

@main
struct gitrelayApp: App {
    @State private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appVM)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        let hasVisibleWindow = NSApp.windows.contains {
                            $0.styleMask.contains(.titled) && $0.isVisible
                        }
                        if !hasVisibleWindow {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)

        Window("About GitRelay", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appVM)
        } label: {
            MenuBarIconLabel(appVM: appVM)
        }
        .menuBarExtraStyle(.window)
    }
}
