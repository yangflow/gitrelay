import SwiftUI

/// Grouped main-window sidebar: 概览 / 账号 / 设置 plus the run footer.
///
/// The item set comes from ``MainSidebarItem`` and is intentionally closed, so
/// this view has no list of its own to drift out of sync.
struct MainSidebarView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selection: MainSidebarItem

    private var queueCount: Int { appVM.syncQueueEntries.count }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: optionalSelection) {
                ForEach(MainSidebarSection.allCases) { section in
                    Section {
                        ForEach(section.items) { item in
                            row(item)
                                .tag(item)
                                .listRowBackground(selectionBackground(isSelected: selection == item))
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            SidebarFooterView(
                summary: appVM.sidebarFooterSummary,
                onTogglePause: { appVM.toggleScheduledSyncPause() }
            )
        }
    }

    /// `List` selection is optional; the pane always has a destination, so a nil
    /// write (⌘-click deselect) is ignored rather than emptying the right side.
    private var optionalSelection: Binding<MainSidebarItem?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                selection = newValue
            }
        )
    }

    @ViewBuilder
    private func row(_ item: MainSidebarItem) -> some View {
        if item == .queue {
            Label(item.title, systemImage: item.systemImage)
                .badge(queueCount)
        } else {
            Label(item.title, systemImage: item.systemImage)
        }
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.control, style: .continuous)
                .fill(DesignTokens.Surface.selectionTint)
                .padding(.horizontal, DesignTokens.Spacing.xxxs)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }
}
