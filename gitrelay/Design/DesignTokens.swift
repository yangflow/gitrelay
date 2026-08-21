import SwiftUI

/// In-repo visual language for the main window chrome.
/// Inspired by Luminare / Ice layout and atmosphere only — no design-system packages.
enum DesignTokens {
    enum Layout {
        /// Narrow sidebar range (Ice-like); keeps filters + repo rows usable.
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarIdealWidth: CGFloat = 240
        static let sidebarMaxWidth: CGFloat = 300

        static let windowMinWidth: CGFloat = 720
        static let windowMinHeight: CGFloat = 500
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
    }

    enum CornerRadius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 10
        static let card: CGFloat = 12
        static let statusDot: CGFloat = 4
    }

    enum Size {
        static let statusDot: CGFloat = 8
        static let searchFieldMinHeight: CGFloat = 28
    }

    /// Semantic status colors shared by sidebar dots and detail labels.
    enum StatusColor {
        static let unknown = Color.secondary
        static let idle = Color.green
        static let ahead = Color.blue
        static let syncing = Color.secondary
        static let diverged = Color.yellow
        static let failed = Color.orange
        static let escalatedFailure = Color.red
        static let pause = Color.orange

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
            case .diverged:
                return diverged
            case .failed:
                return failed
            }
        }
    }

    enum Surface {
        static let searchFieldFill = Color(nsColor: .controlBackgroundColor)
        static let panelFill = Color(nsColor: .controlBackgroundColor)
        static let logFill = Color(nsColor: .textBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
        static let selectionTint = Color.accentColor.opacity(0.12)
        static let badgeFill = Color.red
    }

    /// Materials used for main-window chrome. Ordinary materials on 14/15;
    /// Tahoe may layer an extra translucent wash behind `#available(macOS 26, *)`.
    enum Material {
        case sidebar
        case detail
        case footer

        var swiftUIMaterial: SwiftUI.Material {
            switch self {
            case .sidebar:
                return .sidebar
            case .detail:
                return .contentBackground
            case .footer:
                return .bar
            }
        }
    }

    enum ChromeRole {
        case sidebar
        case detail

        var material: Material {
            switch self {
            case .sidebar: return .sidebar
            case .detail: return .detail
            }
        }
    }
}
