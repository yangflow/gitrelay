import Foundation

enum DestructivePushError: LocalizedError {
    case blocked(DestructivePushPlan)

    var errorDescription: String? {
        switch self {
        case .blocked(let plan):
            return "已阻断破坏性镜像推送: \(plan.summary)。请确认目标仓库 refs 后再将策略改为自动执行。"
        }
    }
}
