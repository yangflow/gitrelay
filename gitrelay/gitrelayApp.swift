import SwiftUI

@main
struct gitrelayApp: App {
    @State private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
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
