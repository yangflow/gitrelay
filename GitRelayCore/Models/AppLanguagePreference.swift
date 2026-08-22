import Foundation

/// In-app UI language: Follow System, English, or Simplified Chinese.
nonisolated enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    /// BCP-47 tag written to `AppleLanguages`, or `nil` to follow the system.
    var appleLanguageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    /// Picker label shown in Settings → 配置.
    var pickerLabel: String {
        switch self {
        case .system:
            String(localized: "Follow System")
        case .english:
            String(localized: "English")
        case .simplifiedChinese:
            String(localized: "Simplified Chinese")
        }
    }
}
