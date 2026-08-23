import SwiftUI

/// Official provider marks used only where provider identity is the content.
struct ProviderBrandIcon: View {
    let provider: GitProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch provider {
            case .github:
                Image("ProviderGitHub")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(.primary)
            case .gitlab:
                Image("ProviderGitLab")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(Color(red: 0.988, green: 0.427, blue: 0.149))
            case .gitea:
                Image("ProviderGitea")
                    .renderingMode(.original)
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A provider identity mark with a neutral fallback for non-host destinations.
/// Keeping the fallback here prevents repository surfaces from inventing their
/// own provider stand-ins.
struct ProviderIdentityIcon: View {
    let provider: GitProvider?
    var size: CGFloat = 16
    var fallbackSystemImage = "externaldrive"

    var body: some View {
        Group {
            if let provider {
                ProviderBrandIcon(provider: provider, size: size)
            } else {
                Image(systemName: fallbackSystemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Consistent provider option used by pickers and compact account metadata.
struct ProviderBrandLabel: View {
    let provider: GitProvider
    var usesShortName = false
    var iconSize: CGFloat = 16

    var body: some View {
        Label {
            Text(usesShortName ? provider.shortName : provider.displayName)
        } icon: {
            ProviderBrandIcon(provider: provider, size: iconSize)
        }
    }
}

/// A compact provider switcher that keeps brand marks visible. AppKit's
/// segmented picker drops custom SwiftUI label icons, so provider identity
/// uses an explicit button group instead.
struct ProviderSegmentedControl: View {
    @Binding var selection: GitProvider
    let providers: [GitProvider]

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxxs) {
            ForEach(providers) { provider in
                Button {
                    selection = provider
                } label: {
                    ProviderBrandLabel(provider: provider)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == provider ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(
                        cornerRadius: DesignTokens.CornerRadius.control,
                        style: .continuous
                    )
                    .fill(selection == provider ? Color.accentColor : Color.clear)
                }
                .accessibilityAddTraits(selection == provider ? .isSelected : [])
            }
        }
        .padding(DesignTokens.Spacing.xxxs)
        .background(.quaternary.opacity(0.7))
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.control + DesignTokens.Spacing.xxxs,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
    }
}
