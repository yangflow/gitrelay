import SwiftUI

@main
struct gitrelayApp: App {
    @State private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appVM)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    // After the window finishes closing, hide from Dock if no
                    // titled window remains visible.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appVM)
        } label: {
            MenuBarIconLabel(appVM: appVM)
        }
        .menuBarExtraStyle(.window)
    }
}
