import Foundation

enum DestructivePushPolicy: String, Codable, CaseIterable, Identifiable {
    case strict
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict: return "严格保护"
        case .auto:   return "自动执行"
        }
    }

    var description: String {
        switch self {
        case .strict:
            return "dry-run 检测到目标侧 ref 删除或强制更新时阻断同步。"
        case .auto:
            return "检测到删除或强制更新也继续推送,适合临时镜像或已确认的目标仓库。"
        }
    }
}
