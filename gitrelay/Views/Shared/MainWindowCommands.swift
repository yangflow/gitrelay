import SwiftUI

/// Menu-bar commands for the main window shortcuts (⌘N / ⌘F / ⌘R).
struct MainWindowCommands: Commands {
    let workspace: WorkspaceModel
    let operations: MirrorOperationsController
    let notifications: NotificationController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(MainWindowShortcutBinding.addRepository.menuTitle) {
                workspace.requestOpenAddMirror()
                notifications.presentMainWindow()
            }
            .keyboardShortcut(
                MainWindowShortcutBinding.addRepository.keyEquivalent,
                modifiers: MainWindowShortcutBinding.addRepository.modifiers
            )
        }

        // `.textFinding` is unavailable on the macOS 14/15 SDK used by CI; place
        // Find after the standard text-editing group so ⌘F still appears in Edit.
        CommandGroup(after: .textEditing) {
            Button(MainWindowShortcutBinding.focusSearch.menuTitle) {
                workspace.requestFocusSearch()
                notifications.presentMainWindow()
            }
            .keyboardShortcut(
                MainWindowShortcutBinding.focusSearch.keyEquivalent,
                modifiers: MainWindowShortcutBinding.focusSearch.modifiers
            )
        }

        CommandMenu(String.loc("Mirror")) {
            Button(MainWindowShortcutBinding.syncSelected.menuTitle) {
                if let id = workspace.selectedMirrorID {
                    operations.triggerSync(mirrorID: id)
                }
            }
            .keyboardShortcut(
                MainWindowShortcutBinding.syncSelected.keyEquivalent,
                modifiers: MainWindowShortcutBinding.syncSelected.modifiers
            )

            // The pair table keeps only search and add, so Sync All lives here.
            Button(String.loc("Sync All")) {
                operations.triggerSyncAll()
            }
        }
    }
}

/// Keeps the conventional macOS Settings menu and ⌘, shortcut while the
/// settings interface lives in a normal window, matching the main workspace.
struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(String.loc("Settings…")) {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
