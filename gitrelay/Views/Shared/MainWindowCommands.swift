import SwiftUI

/// Menu-bar commands for the main window shortcuts (⌘N / ⌘F / ⌘R).
struct MainWindowCommands: Commands {
    let appVM: AppViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(MainWindowShortcutBinding.addRepository.menuTitle) {
                appVM.requestOpenAddRepository()
            }
            .keyboardShortcut(
                MainWindowShortcutBinding.addRepository.keyEquivalent,
                modifiers: MainWindowShortcutBinding.addRepository.modifiers
            )
        }

        CommandGroup(replacing: .textFinding) {
            Button(MainWindowShortcutBinding.focusSearch.menuTitle) {
                appVM.requestFocusSidebarSearch()
            }
            .keyboardShortcut(
                MainWindowShortcutBinding.focusSearch.keyEquivalent,
                modifiers: MainWindowShortcutBinding.focusSearch.modifiers
            )
        }

        CommandMenu(String(localized: "Repository")) {
            Button(MainWindowShortcutBinding.syncSelected.menuTitle) {
                appVM.syncMainWindowSelectedRepository()
            }
            .keyboardShortcut(
                MainWindowShortcutBinding.syncSelected.keyEquivalent,
                modifiers: MainWindowShortcutBinding.syncSelected.modifiers
            )
        }
    }
}
