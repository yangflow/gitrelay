import Foundation
import Observation

/// Persists main-window selection, detail tab, and sidebar width in UserDefaults (no secrets).
@MainActor
@Observable
final class WindowLayoutStore {
    private enum Keys {
        static let selectedRepoID = "WindowLayout.selectedRepoID"
        static let selectedSmartView = "WindowLayout.selectedSmartView"
        static let detailTab = "WindowLayout.detailTab"
        static let sidebarWidth = "WindowLayout.sidebarWidth"
    }

    private let defaults: UserDefaults
    private var storage: WindowLayout

    var layout: WindowLayout {
        get { storage }
        set {
            storage = Self.normalized(newValue)
            persist(storage)
        }
    }

    var selectedRepoID: UUID? {
        get { storage.selectedRepoID }
        set {
            guard storage.selectedRepoID != newValue else { return }
            storage.selectedRepoID = newValue
            persistSelectedRepoID(newValue)
        }
    }

    var selectedSmartView: MirrorSmartView? {
        get { storage.selectedSmartView }
        set {
            guard storage.selectedSmartView != newValue else { return }
            storage.selectedSmartView = newValue
            if let newValue {
                defaults.set(newValue.id, forKey: Keys.selectedSmartView)
            } else {
                defaults.removeObject(forKey: Keys.selectedSmartView)
            }
        }
    }

    var detailTab: RepoDetailTab {
        get { storage.detailTab }
        set {
            guard storage.detailTab != newValue else { return }
            storage.detailTab = newValue
            defaults.set(newValue.rawValue, forKey: Keys.detailTab)
        }
    }

    var sidebarWidth: CGFloat {
        get { CGFloat(storage.sidebarWidth) }
        set {
            // Ignore transient GeometryReader zeroes / out-of-range probes.
            let minWidth = DesignTokens.Layout.sidebarMinWidth
            let maxWidth = DesignTokens.Layout.sidebarMaxWidth
            guard newValue >= minWidth - 0.5, newValue <= maxWidth + 0.5 else { return }
            let clamped = WindowLayout.clampedSidebarWidth(Double(newValue))
            guard abs(storage.sidebarWidth - clamped) >= 0.5 else { return }
            storage.sidebarWidth = clamped
            defaults.set(clamped, forKey: Keys.sidebarWidth)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storage = Self.normalized(Self.load(from: defaults))
    }

    /// Clears selection when the stored id is not among existing repos (no ghost id).
    func reconcileSelection(withExistingIDs existingIDs: Set<UUID>) {
        let reconciled = storage.reconciled(withExistingIDs: existingIDs)
        guard reconciled.selectedRepoID != storage.selectedRepoID else { return }
        selectedRepoID = reconciled.selectedRepoID
    }

    func resetToDefaults() {
        layout = .default
    }

    private func persist(_ value: WindowLayout) {
        persistSelectedRepoID(value.selectedRepoID)
        if let selectedSmartView = value.selectedSmartView {
            defaults.set(selectedSmartView.id, forKey: Keys.selectedSmartView)
        } else {
            defaults.removeObject(forKey: Keys.selectedSmartView)
        }
        defaults.set(value.detailTab.rawValue, forKey: Keys.detailTab)
        defaults.set(value.sidebarWidth, forKey: Keys.sidebarWidth)
    }

    private func persistSelectedRepoID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: Keys.selectedRepoID)
        } else {
            defaults.removeObject(forKey: Keys.selectedRepoID)
        }
    }

    private static func normalized(_ value: WindowLayout) -> WindowLayout {
        var copy = value
        copy.sidebarWidth = WindowLayout.clampedSidebarWidth(copy.sidebarWidth)
        return copy
    }

    private static func load(from defaults: UserDefaults) -> WindowLayout {
        let fallback = WindowLayout.default

        let selectedRepoID: UUID?
        if let raw = defaults.string(forKey: Keys.selectedRepoID) {
            selectedRepoID = UUID(uuidString: raw)
        } else {
            selectedRepoID = nil
        }

        let detailTab: RepoDetailTab
        if let raw = defaults.string(forKey: Keys.detailTab),
           let parsed = RepoDetailTab(rawValue: raw)
        {
            detailTab = parsed
        } else {
            detailTab = fallback.detailTab
        }

        let selectedSmartView = defaults.string(forKey: Keys.selectedSmartView)
            .flatMap(MirrorSmartView.init(id:))

        let sidebarWidth: Double
        if defaults.object(forKey: Keys.sidebarWidth) == nil {
            sidebarWidth = fallback.sidebarWidth
        } else {
            sidebarWidth = WindowLayout.clampedSidebarWidth(defaults.double(forKey: Keys.sidebarWidth))
        }

        return WindowLayout(
            selectedRepoID: selectedRepoID,
            selectedSmartView: selectedSmartView,
            detailTab: detailTab,
            sidebarWidth: sidebarWidth
        )
    }
}
