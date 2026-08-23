import AppKit
import SwiftUI

struct AboutView: View {
    private static let githubURL = URL(string: "https://github.com/yangflow/gitrelay")

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.aboutSection) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(
                    width: DesignTokens.Layout.aboutIconSize,
                    height: DesignTokens.Layout.aboutIconSize
                )
                .accessibilityHidden(true)
                .padding(.bottom, DesignTokens.Spacing.sm)

            Text("GitRelay")
                .font(.title2.weight(.bold))

            Text(String(format: String.loc("Version %@ (%@)"), version, build))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(String.loc("© 2026 yangflow · MIT License"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, DesignTokens.Spacing.md)
                .accessibilityIdentifier("about.license")

            HStack(spacing: DesignTokens.Spacing.lg) {
                Button {
                    guard let url = Self.githubURL else { return }
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(String.loc("GitHub"), systemImage: "link")
                }
                .accessibilityIdentifier("about.github")

                Button {
                    UpdaterService.shared.checkForUpdates()
                } label: {
                    Label(String.loc("Check for Updates"), systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("about.check-for-updates")
            }
            .buttonStyle(.link)
            .padding(.top, DesignTokens.Spacing.lg)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(width: DesignTokens.Layout.aboutWidth)
        .fixedSize()
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String.loc("About GitRelay")) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
        }
    }
}
