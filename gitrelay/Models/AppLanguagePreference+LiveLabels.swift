import Foundation

extension AppLanguagePreference {
    /// Picker label that follows the in-app language choice.
    var livePickerLabel: String {
        switch self {
        case .system:
            String.loc("Follow System")
        case .english:
            String.loc("English")
        case .simplifiedChinese:
            String.loc("Simplified Chinese")
        }
    }
}
