import Foundation

nonisolated enum MirrorTargetKind: String, Codable, CaseIterable, Identifiable {
    case gitRemote
    case filesystem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gitRemote: return String.loc("Git Remote")
        case .filesystem: return String.loc("Filesystem Archive")
        }
    }
}
