import AppKit
import SwiftUI

/// Shared visual language for app chrome, settings, sheets, menu bar, and widgets.
/// Inspired by Luminare / Ice layout and atmosphere only — no design-system packages.
/// Lives in GitRelayCore so the app and widget targets share one token source.
enum DesignTokens {
    enum Layout {
        /// Narrow sidebar range (Ice-like); keeps filters + repo rows usable.
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarIdealWidth: CGFloat = 240
        static let sidebarMaxWidth: CGFloat = 300

        static let windowMinWidth: CGFloat = 720
        static let windowMinHeight: CGFloat = 500

        static let popoverWidth: CGFloat = 280
        static let popoverListMaxHeight: CGFloat = 280
        /// Overall Settings window (narrow sidebar + detail form).
        static let settingsMinWidth: CGFloat = 560
        static let settingsMinHeight: CGFloat = 420
        static let settingsSidebarMinWidth: CGFloat = 140
        static let settingsSidebarIdealWidth: CGFloat = 160
        static let settingsSidebarMaxWidth: CGFloat = 200
        static let settingsDetailMinWidth: CGFloat = 380
        static let verificationSettingsMinHeight: CGFloat = 240
        static let orgSubscriptionSettingsMinHeight: CGFloat = 320
        static let aboutWidth: CGFloat = 280
        static let aboutIconSize: CGFloat = 80

        /// Add / Edit repository sheet — resizable; floor matches the locked two-column mockup.
        static let addEditRepoSheetMinWidth: CGFloat = 640
        static let addEditRepoSheetMinHeight: CGFloat = 420

        /// 添加令牌 sheet: one narrow column of provider, name, host, token.
        static let addProviderTokenSheetWidth: CGFloat = 440

        /// Browse-remote wizard rail: keeps 1–2–3 centered instead of stretching
        /// across a wide, resized detail pane.
        static let browseStepBarMaxWidth: CGFloat = 320
        /// Repository picker keeps a workable height on a short window.
        static let browseRepoListMinHeight: CGFloat = 200

        /// Pair-table column sizing (源 / 目标 / 状态 / 上次).
        static let pairTablePathColumnMin: CGFloat = 140
        static let pairTablePathColumnIdeal: CGFloat = 220
        static let pairTableStatusColumnMin: CGFloat = 80
        static let pairTableStatusColumnIdeal: CGFloat = 96
        static let pairTableLastColumnMin: CGFloat = 80
        static let pairTableLastColumnIdeal: CGFloat = 104
        /// Determinate-free progress bar in the queue pane.
        static let queueProgressWidth: CGFloat = 170
    }

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24

        static let sidebarChromeVertical: CGFloat = 10
        static let sidebarChromeHorizontal: CGFloat = 12
        static let detailContent: CGFloat = 20
        static let detailSection: CGFloat = 20
        static let rowVertical: CGFloat = 4
        static let statusDotGap: CGFloat = 8

        static let sheetHeaderHorizontal: CGFloat = 20
        static let sheetHeaderTop: CGFloat = 20
        static let sheetHeaderBottom: CGFloat = 12
        static let sheetFooter: CGFloat = 16
        static let sheetContent: CGFloat = 20
        static let formFieldGap: CGFloat = 6
        static let chipHorizontal: CGFloat = 8
        static let chipVertical: CGFloat = 4
        static let popoverChromeHorizontal: CGFloat = 12
        static let popoverChromeVertical: CGFloat = 10
        static let settingsForm: CGFloat = 16
        static let aboutSection: CGFloat = 6

        static let paneHeaderHorizontal: CGFloat = 20
        static let paneHeaderTop: CGFloat = 18
        static let paneHeaderBottom: CGFloat = 12
        static let paneTabGap: CGFloat = 18
    }

    enum CornerRadius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 10
        static let card: CGFloat = 12
        static let statusDot: CGFloat = 4
        static let chip: CGFloat = 3
        static let banner: CGFloat = 8
    }

    enum Size {
        static let statusDot: CGFloat = 8
        static let searchFieldMinHeight: CGFloat = 28
        static let menuBarIconPointSize: CGFloat = 16
        static let aboutIcon: CGFloat = 80
        static let runIndicatorDot: CGFloat = 7
        static let paneTabUnderline: CGFloat = 2
        /// Numbered circle on the browse-remote step rail.
        static let stepMarker: CGFloat = 26
    }

    /// Semantic status colors shared by sidebar dots, detail labels, menu bar, and widgets.
    enum StatusColor {
        static let unknown = Color.secondary
        static let idle = Color.green
        static let ahead = Color.blue
        static let syncing = Color.secondary
        static let queued = Color.secondary
        static let diverged = Color.yellow
        static let failed = Color.orange
        static let escalatedFailure = Color.red
        static let pause = Color.orange

        /// Alias for success / healthy states (matches idle green).
        static let success = idle
        /// Alias for destructive / error copy (matches escalated red).
        static let error = escalatedFailure
        /// Alias for caution / incomplete-auth banners (matches failed orange).
        static let warning = failed
        /// Informational accent (ahead / reused).
        static let info = ahead

        static func forStatus(_ status: SyncStatus) -> Color {
            switch status {
            case .unknown:
                return unknown
            case .idle:
                return idle
            case .ahead:
                return ahead
            case .syncing:
                return syncing
            case .queued:
                return queued
            case .diverged:
                return diverged
            case .failed:
                return failed
            }
        }

        static func forMenuBarStatusTone(_ tone: MenuBarStatusTone) -> Color {
            switch tone {
            case .pause:
                return pause
            case .info:
                return info
            }
        }

        static func forWidgetStatus(_ status: RepoSyncStatusKind) -> Color {
            switch status {
            case .success:
                return success
            case .failure:
                return escalatedFailure
            case .syncing:
                return syncing
            case .queued:
                return queued
            case .diverged:
                return diverged
            case .unknown:
                return unknown
            }
        }

        /// Stable label for tests without importing SwiftUI Color equality.
        static func label(for status: SyncStatus) -> String {
            switch status {
            case .unknown: return "unknown"
            case .idle: return "idle"
            case .ahead: return "ahead"
            case .syncing: return "syncing"
            case .queued: return "queued"
            case .diverged: return "diverged"
            case .failed: return "failed"
            }
        }

        static func label(forWidgetStatus status: RepoSyncStatusKind) -> String {
            switch status {
            case .success: return "success"
            case .failure: return "failure"
            case .syncing: return "syncing"
            case .queued: return "queued"
            case .diverged: return "diverged"
            case .unknown: return "unknown"
            }
        }
    }

    enum Surface {
        static let searchFieldFill = Color(nsColor: .controlBackgroundColor)
        static let panelFill = Color(nsColor: .controlBackgroundColor)
        static let logFill = Color(nsColor: .textBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
        /// Sidebar selection pill (stock macOS 14+ calm accent wash).
        static let selectionTint = Color.accentColor.opacity(0.18)
        static let badgeFill = Color.red
        static let chipFill = Color.primary.opacity(0.08)
        static let suggestionFill = Color.primary.opacity(0.06)
        static let bannerSuccessFill = StatusColor.success.opacity(0.12)
        static let bannerWarningFill = StatusColor.warning.opacity(0.12)
        static let destructiveFill = StatusColor.error.opacity(0.08)
        static let forceUpdateFill = StatusColor.warning.opacity(0.08)
    }

    /// AppKit visual-effect materials for window chrome.
    /// Ordinary materials on 14/15; Tahoe may layer an extra wash behind `#available(macOS 26, *)`.
    enum Material: Equatable {
        case sidebar
        case detail
        case footer
        case popover
        case sheet

        var tokenName: String {
            switch self {
            case .sidebar: return "sidebar"
            case .detail: return "detail"
            case .footer: return "footer"
            case .popover: return "popover"
            case .sheet: return "sheet"
            }
        }

        var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .sidebar:
                // Stock sidebar material (reads as under-page / source-list depth).
                return .sidebar
            case .detail:
                // Flat detail plane (window / content background).
                return .contentBackground
            case .footer:
                return .headerView
            case .popover:
                return .popover
            case .sheet:
                return .contentBackground
            }
        }

        var blendingMode: NSVisualEffectView.BlendingMode {
            switch self {
            case .sidebar, .footer, .popover:
                return .behindWindow
            case .detail, .sheet:
                return .withinWindow
            }
        }
    }

    enum ChromeRole: Equatable {
        case sidebar
        case detail
        case popover
        case sheet

        var material: Material {
            switch self {
            case .sidebar: return .sidebar
            case .detail: return .detail
            case .popover: return .popover
            case .sheet: return .sheet
            }
        }
    }
}

/// Thin `NSVisualEffectView` wrapper (same approach as Ice / Luminare atmosphere).
struct GitRelayVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Plain status color dot for widget attention rows (same palette as app ``StatusDotView``).
struct WidgetStatusDotView: View {
    let status: RepoSyncStatusKind

    var body: some View {
        Circle()
            .fill(DesignTokens.StatusColor.forWidgetStatus(status))
            .frame(
                width: DesignTokens.Size.statusDot,
                height: DesignTokens.Size.statusDot
            )
            .accessibilityHidden(true)
    }
}
