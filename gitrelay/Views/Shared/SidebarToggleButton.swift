import SwiftUI

/// In-content sidebar show/hide control (never placed in the window toolbar).
struct SidebarToggleButton: View {
    @Environment(WindowLayoutStore.self) private var windowLayout

    var body: some View {
        Button {
            windowLayout.sidebarVisible.toggle()
        } label: {
            Image(
                systemName: windowLayout.sidebarVisible
                    ? "sidebar.left"
                    : "sidebar.leading"
            )
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(QuietPressButtonStyle())
        .help(String.loc("Toggle Sidebar"))
        .accessibilityLabel(String.loc("Toggle Sidebar"))
    }
}
