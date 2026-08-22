import SwiftUI

/// Main-window menu commands and their key equivalents (issue #69).
enum MainWindowShortcutBinding: String, CaseIterable, Sendable {
    case addRepository
    case focusSearch
    case syncSelected

    /// Character under ⌘ for unit tests and menu wiring.
    var keyCharacter: Character {
        switch self {
        case .addRepository: "n"
        case .focusSearch: "f"
        case .syncSelected: "r"
        }
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(keyCharacter)
    }

    /// ⌘ only — exposed as a Bool so unit tests need no SwiftUI import.
    var isCommandOnly: Bool { true }

    var modifiers: EventModifiers { .command }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: modifiers)
    }

    var menuTitle: String {
        switch self {
        case .addRepository:
            String.loc("Add Repository")
        case .focusSearch:
            String.loc("Search Repositories")
        case .syncSelected:
            String.loc("Sync Selected Repository")
        }
    }
}
