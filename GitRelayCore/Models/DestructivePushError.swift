import Foundation

enum DestructivePushError: LocalizedError {
    case blocked(DestructivePushPlan)

    var errorDescription: String? {
        switch self {
        case .blocked(let plan):
            return String(localized: "Destructive mirror push blocked: \(plan.summary). Sync again and choose Push to Check Branch to keep the target's branches, or Overwrite and Sync to replace them.")
        }
    }
}
