import Foundation
import Testing
@testable import GitRelay

@Suite("AppLanguageStore")
@MainActor
struct AppLanguageStoreTests {
    private func freshDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "gitrelay.tests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test func defaultsToSystem() {
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        #expect(store.preference == .system)
        #expect(store.preference.appleLanguageCode == nil)
    }

    @Test func persistingEnglishWritesAppleLanguages() {
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .english

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "english")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
        #expect(store.locale.identifier.hasPrefix("en"))
    }

    @Test func theNoteAppearsOnlyAfterAChange() {
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        let quietAtLaunch = store.showsLaunchCatalogNote

        store.preference = .english
        let afterChange = store.showsLaunchCatalogNote

        #expect(!quietAtLaunch)
        #expect(afterChange)
    }

    @Test func persistingSimplifiedChineseWritesAppleLanguages() {
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .simplifiedChinese

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "simplifiedChinese")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }

    @Test func returningToSystemClearsAppleLanguagesOverride() {
        let (defaults, suiteName) = freshDefaults()
        defaults.set(["en"], forKey: "AppleLanguages")
        defaults.set(AppLanguagePreference.english.rawValue, forKey: AppLanguageStore.preferenceKey)
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .system

        // Suite defaults fall back to the host AppleLanguages when read through
        // `object(forKey:)`, so assert against the suite's own persistent domain.
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)
        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "system")
    }

    @Test func bootstrapAppliesStoredPreference() {
        let (defaults, _) = freshDefaults()
        defaults.set(AppLanguagePreference.simplifiedChinese.rawValue, forKey: AppLanguageStore.preferenceKey)

        AppLanguageStore.bootstrapAppleLanguages(defaults: defaults)

        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }
}

@Suite("AppLocalization")
struct AppLocalizationTests {
    @Test func resolvesBareLanguageCodes() {
        let available = ["en", "zh-Hans", "Base"]
        #expect(AppLocalization.localizationName(for: "zh-Hans", available: available) == "zh-Hans")
        #expect(AppLocalization.localizationName(for: "en", available: available) == "en")
    }
}
