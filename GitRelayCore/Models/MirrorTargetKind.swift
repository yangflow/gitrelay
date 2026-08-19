import Foundation

enum MirrorTargetKind: String, Codable, CaseIterable, Identifiable {
    case gitRemote
    case filesystem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gitRemote: return "Git 远程"
        case .filesystem: return "文件系统归档"
        }
    }
}
