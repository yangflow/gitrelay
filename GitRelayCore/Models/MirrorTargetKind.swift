import Foundation

enum MirrorTargetKind: String, Codable, CaseIterable, Identifiable {
    case gitRemote
    case filesystem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gitRemote: return "Git Remote"
        case .filesystem: return "Filesystem Archive"
        }
    }
}
