import SwiftUI

/// Applies chrome materials from ``DesignTokens``.
/// Sidebar and popover rely on system materials; detail and sheets use
/// ``GitRelayVisualEffectView`` only.
struct GitRelayChromeBackground: View {
    let role: DesignTokens.ChromeRole

    var body: some View {
        GitRelayVisualEffectView(
            material: role.material.nsMaterial,
            blendingMode: role.material.blendingMode
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Pins the main-window sidebar to the narrow DesignTokens width range.
    /// - Parameter ideal: Restored or current column width (clamped by min/max).
    func gitRelaySidebarColumnWidth(
        ideal: CGFloat = DesignTokens.Layout.sidebarIdealWidth
    ) -> some View {
        let clampedIdeal = min(
            max(ideal, DesignTokens.Layout.sidebarMinWidth),
            DesignTokens.Layout.sidebarMaxWidth
        )
        return frame(
            minWidth: DesignTokens.Layout.sidebarMinWidth,
            idealWidth: clampedIdeal,
            maxWidth: DesignTokens.Layout.sidebarMaxWidth
        )
    }

    /// Pins the Settings sidebar to the narrow DesignTokens width range.
    func gitRelaySettingsSidebarColumnWidth() -> some View {
        navigationSplitViewColumnWidth(
            min: DesignTokens.Layout.settingsSidebarMinWidth,
            ideal: DesignTokens.Layout.settingsSidebarIdealWidth,
            max: DesignTokens.Layout.settingsSidebarMaxWidth
        )
    }

    func gitRelayChrome(_ role: DesignTokens.ChromeRole) -> some View {
        background {
            GitRelayChromeBackground(role: role)
        }
    }

    /// Soft panel surface used inside the detail scroll (logs, callouts, etc.).
    /// Low-contrast fill + hairline only — no drop shadow (including dark mode).
    func gitRelayPanelSurface(
        fill: Color = DesignTokens.Surface.panelFill,
        cornerRadius: CGFloat = DesignTokens.CornerRadius.control
    ) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DesignTokens.Surface.separator, lineWidth: 1)
            }
    }

    /// Standard sheet header / footer padding from DesignTokens.
    func gitRelaySheetHeaderPadding() -> some View {
        padding(.horizontal, DesignTokens.Spacing.sheetHeaderHorizontal)
            .padding(.top, DesignTokens.Spacing.sheetHeaderTop)
            .padding(.bottom, DesignTokens.Spacing.sheetHeaderBottom)
    }

    func gitRelaySheetFooterPadding() -> some View {
        padding(DesignTokens.Spacing.sheetFooter)
    }
}

/// Quiet press feedback for chrome controls (toolbar, empty-state text links).
struct QuietPressButtonStyle: ButtonStyle {
    var pressedOpacity: Double = 0.55

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Compact status color dot for sidebar and menu-bar rows (Ice / Luminare atmosphere).
struct StatusDotView: View {
    let status: SyncStatus
    /// When false, ahead state is a plain blue dot (detail labels already show the count).
    var showsAheadCount: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Group {
            switch status {
            case .syncing:
                Circle()
                    .strokeBorder(DesignTokens.StatusColor.syncing, lineWidth: 1.5)
                    .overlay {
                        Circle()
                            .fill(DesignTokens.StatusColor.syncing.opacity(0.35))
                            .scaleEffect(reduceMotion ? 1 : (isPulsing ? 0.55 : 0.85))
                    }
                    .frame(
                        width: DesignTokens.Size.statusDot,
                        height: DesignTokens.Size.statusDot
                    )
                    .task {
                        guard !reduceMotion else {
                            isPulsing = true
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                    .onDisappear { isPulsing = false }
            case .queued:
                Circle()
                    .strokeBorder(DesignTokens.StatusColor.queued, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .frame(
                        width: DesignTokens.Size.statusDot,
                        height: DesignTokens.Size.statusDot
                    )
            case .ahead(let count) where showsAheadCount:
                HStack(spacing: DesignTokens.Spacing.xxxs) {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(DesignTokens.StatusColor.ahead)
                    Circle()
                        .fill(DesignTokens.StatusColor.ahead)
                        .frame(
                            width: DesignTokens.Size.statusDot,
                            height: DesignTokens.Size.statusDot
                        )
                }
            default:
                Circle()
                    .fill(DesignTokens.StatusColor.forStatus(status))
                    .frame(
                        width: DesignTokens.Size.statusDot,
                        height: DesignTokens.Size.statusDot
                    )
            }
        }
        .frame(minWidth: DesignTokens.Size.statusDot, minHeight: DesignTokens.Size.statusDot)
        .frame(width: showsAheadCount ? 18 : DesignTokens.Size.statusDot, alignment: .trailing)
        .accessibilityHidden(true)
    }
}
