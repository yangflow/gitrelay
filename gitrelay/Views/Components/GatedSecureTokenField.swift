import SwiftUI

/// Secure token field with an optional reveal toggle gated by biometric authentication.
struct GatedSecureTokenField: View {
    @Environment(AppViewModel.self) private var appVM

    let placeholder: LocalizedStringKey
    @Binding var text: String

    @State private var isRevealed = false
    @State private var isAuthenticating = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))

            Button {
                Task { await toggleReveal() }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? String(localized: "Hide Token") : String(localized: "Show Token"))
            .disabled(isAuthenticating || text.isEmpty)
        }
    }

    private func toggleReveal() async {
        if isRevealed {
            isRevealed = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard await appVM.authorizeSensitiveAction(.revealToken) else { return }
        isRevealed = true
    }
}
