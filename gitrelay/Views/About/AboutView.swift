import SwiftUI
import AppKit

/// The system About panel, not a landing page (#88): app icon, name, version,
/// and two quiet links. The icon is whatever the bundle ships, so the Y-branch
/// AppIcon is the only mark here — there is no second logotype.
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

            Text(String(localized: "GitRelay"))
                .font(.title3.weight(.semibold))

            Text(String(localized: "Version \(version) (\(build))"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: DesignTokens.Spacing.lg) {
                Button(String(localized: "GitHub")) {
                    guard let url = Self.githubURL else { return }
                    NSWorkspace.shared.open(url)
                }
                Button(String(localized: "Check for Updates")) {
                    UpdaterService.shared.checkForUpdates()
                }
            }
            .buttonStyle(.link)
            .padding(.top, DesignTokens.Spacing.md)

            Text(String(localized: "© 2026 yangflow · MIT License"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, DesignTokens.Spacing.md)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(width: DesignTokens.Layout.aboutWidth)
        .fixedSize()
        .gitRelayChrome(.sheet)
    }
}
