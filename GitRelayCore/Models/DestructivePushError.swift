import Foundation

enum DestructivePushError: LocalizedError {
    case blocked(DestructivePushPlan)

    var errorDescription: String? {
        switch self {
        case .blocked(let plan):
            return "Destructive mirror push blocked: \(plan.summary). Sync again and choose Continue in the confirmation dialog, or change the policy to Run Automatically."
        }
    }
}
