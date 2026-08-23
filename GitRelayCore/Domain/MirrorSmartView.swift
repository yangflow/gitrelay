import Foundation

/// A derived workspace scope. Smart views are navigation state, never mirror data.
nonisolated enum MirrorSmartView: Hashable, Identifiable, Sendable {
    case needsAttention
    case allMirrors
    case running
    case paused
    case label(String)

    var id: String {
        switch self {
        case .needsAttention:
            "needs-attention"
        case .allMirrors:
            "all-mirrors"
        case .running:
            "running"
        case .paused:
            "paused"
        case .label(let label):
            "label:\(label)"
        }
    }

    init?(id: String) {
        switch id {
        case "needs-attention":
            self = .needsAttention
        case "all-mirrors":
            self = .allMirrors
        case "running":
            self = .running
        case "paused":
            self = .paused
        default:
            let prefix = "label:"
            guard id.hasPrefix(prefix) else { return nil }
            let label = String(id.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            self = .label(label)
        }
    }
}

/// The minimum cross-feature state needed to answer workspace membership queries.
nonisolated struct MirrorSmartViewContext: Equatable, Sendable {
    var mirrorID: UUID
    var labels: [String]
    var health: MirrorHealthState
    var activity: MirrorActivityState
    var schedule: MirrorScheduleState
    var needsCredentials: Bool

    init(
        mirrorID: UUID,
        labels: [String],
        health: MirrorHealthState,
        activity: MirrorActivityState,
        schedule: MirrorScheduleState,
        needsCredentials: Bool = false
    ) {
        self.mirrorID = mirrorID
        self.labels = labels
        self.health = health
        self.activity = activity
        self.schedule = schedule
        self.needsCredentials = needsCredentials
    }
}

/// Pure membership and count rules shared by the workspace and tests.
nonisolated enum MirrorSmartViewQuery {
    static let primaryViews: [MirrorSmartView] = [
        .needsAttention,
        .allMirrors,
        .running,
        .paused,
    ]

    static func availableViews(in contexts: [MirrorSmartViewContext]) -> [MirrorSmartView] {
        primaryViews + labels(in: contexts).map(MirrorSmartView.label)
    }

    static func labels(in contexts: [MirrorSmartViewContext]) -> [String] {
        var canonicalByFoldedLabel: [String: String] = [:]
        for label in contexts.flatMap(\.labels) {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let folded = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            if canonicalByFoldedLabel[folded] == nil {
                canonicalByFoldedLabel[folded] = trimmed
            }
        }
        return canonicalByFoldedLabel.values.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func count(
        for view: MirrorSmartView,
        in contexts: [MirrorSmartViewContext]
    ) -> Int {
        contexts.lazy.filter { contains($0, in: view) }.count
    }

    static func mirrorIDs(
        in view: MirrorSmartView,
        contexts: [MirrorSmartViewContext]
    ) -> Set<UUID> {
        Set(contexts.lazy.filter { contains($0, in: view) }.map(\.mirrorID))
    }

    static func defaultSelection(in contexts: [MirrorSmartViewContext]) -> MirrorSmartView {
        count(for: .needsAttention, in: contexts) > 0 ? .needsAttention : .allMirrors
    }

    static func reconciledSelection(
        _ selection: MirrorSmartView?,
        in contexts: [MirrorSmartViewContext]
    ) -> MirrorSmartView {
        guard let selection,
              availableViews(in: contexts).contains(selection) else {
            return defaultSelection(in: contexts)
        }
        return selection
    }

    static func contains(
        _ context: MirrorSmartViewContext,
        in view: MirrorSmartView
    ) -> Bool {
        switch view {
        case .needsAttention:
            return context.needsCredentials || healthNeedsAttention(context.health)
        case .allMirrors:
            return true
        case .running:
            if case .idle = context.activity { return false }
            return true
        case .paused:
            switch context.schedule {
            case .mirrorPaused, .globallyPaused, .deferred:
                return true
            case .active:
                return false
            }
        case .label(let selectedLabel):
            return context.labels.contains {
                $0.compare(
                    selectedLabel,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
        }
    }

    private static func healthNeedsAttention(_ health: MirrorHealthState) -> Bool {
        switch health {
        case .needsSetup, .neverRun, .stale, .failed, .diverged:
            true
        case .healthy:
            false
        }
    }
}
