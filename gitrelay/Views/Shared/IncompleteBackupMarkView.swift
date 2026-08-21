import SwiftUI

/// Caution mark for sidebar / menu-bar rows when the mirror is not a full backup.
struct IncompleteBackupMarkView: View {
    let helpText: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(DesignTokens.StatusColor.warning)
            .help(helpText)
            .accessibilityLabel(String(localized: "Incomplete backup"))
            .accessibilityHint(helpText)
    }
}
