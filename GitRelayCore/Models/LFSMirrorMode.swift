import Foundation

/// Per-repo switch for mirroring Git LFS objects after a successful git sync.
nonisolated enum LFSMirrorMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String.loc("Automatic")
        case .off:  return String.loc("Off")
        }
    }

    var description: String {
        switch self {
        case .auto:
            return String.loc("When the source uses Git LFS, fetch all LFS objects into the local mirror and push them to each destination. Requires git-lfs.")
        case .off:
            return String.loc("Skip Git LFS objects. Only Git pointers are mirrored.")
        }
    }
}
