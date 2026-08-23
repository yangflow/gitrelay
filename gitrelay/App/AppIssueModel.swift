import Observation

@MainActor
@Observable
final class AppIssueModel {
    var errorMessage: String?

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func report(_ message: String) {
        errorMessage = message
    }
}
