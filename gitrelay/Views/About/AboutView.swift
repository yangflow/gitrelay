import SwiftUI
import AppKit

/// The system About panel, not a landing page (#88): app icon, name, version,
/// and two quiet links. The icon is whatever the bundle ships via
/// `NSApp.applicationIconImage` — there is no second logotype.
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    private static let githubURL = URL(string: "https://github.com/yangflow/gitrelay")

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

            Text(String.loc("GitRelay"))
                .font(.title3.weight(.semibold))

            Text(String(format: String.loc("Version %@ (%@)"), version, build))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: DesignTokens.Spacing.lg) {
                Button(String.loc("GitHub")) {
                    guard let url = Self.githubURL else { return }
                    NSWorkspace.shared.open(url)
                }
                Button(String.loc("Check for Updates")) {
                    UpdaterService.shared.checkForUpdates()
                }
            }
            .buttonStyle(.link)
            .padding(.top, DesignTokens.Spacing.md)

            Text(String.loc("© 2026 yangflow · MIT License"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, DesignTokens.Spacing.md)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(width: DesignTokens.Layout.aboutWidth)
        .fixedSize()
    }
}
