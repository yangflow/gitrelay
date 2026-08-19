import Foundation

enum DestructivePushError: LocalizedError {
    case blocked(DestructivePushPlan)

    var errorDescription: String? {
        switch self {
        case .blocked(let plan):
            return "已阻断破坏性镜像推送: \(plan.summary)。可再次同步并在确认弹窗中选择继续,或将策略改为自动执行。"
        }
    }
}
