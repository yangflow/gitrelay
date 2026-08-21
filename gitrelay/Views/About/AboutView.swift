import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    private static let githubURL = URL(string: "https://github.com/yangflow/gitrelay")

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: DesignTokens.Spacing.xxl)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(
                    width: DesignTokens.Layout.aboutIconSize,
                    height: DesignTokens.Layout.aboutIconSize
                )

            Text("GitRelay")
                .font(.title.weight(.bold))
                .padding(.top, DesignTokens.Spacing.md)

            Text(String(localized: "Version \(version) (\(build))"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, DesignTokens.Spacing.xxs)
                .textSelection(.enabled)

            Spacer().frame(height: DesignTokens.Spacing.xl)

            VStack(spacing: DesignTokens.Spacing.aboutSection) {
                Text("© 2026 yangflow")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: DesignTokens.Spacing.lg)

            HStack(spacing: DesignTokens.Spacing.md) {
                Button {
                    if let url = Self.githubURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "link")
                }

                Button {
                    UpdaterService.shared.checkForUpdates()
                } label: {
                    Label(String(localized: "Check for Updates"), systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)

            Spacer().frame(height: DesignTokens.Spacing.xxl)
        }
        .frame(width: DesignTokens.Layout.aboutWidth)
        .fixedSize()
        .gitRelayChrome(.sheet)
    }
}
