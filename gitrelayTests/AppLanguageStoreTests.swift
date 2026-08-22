import Foundation
import Testing
@testable import GitRelay

@Suite("AppLanguageStore")
@MainActor
struct AppLanguageStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "gitrelay.tests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsToSystem() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        #expect(store.preference == .system)
        #expect(store.preference.appleLanguageCode == nil)
    }

    @Test func persistingEnglishWritesAppleLanguages() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .english

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "english")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
        #expect(store.locale.identifier.hasPrefix("en"))
    }

    @Test func theNoteAppearsOnlyAfterAChange() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        let quietAtLaunch = store.showsLaunchCatalogNote

        store.preference = .english
        let afterChange = store.showsLaunchCatalogNote

        #expect(!quietAtLaunch)
        #expect(afterChange)
    }

    @Test func persistingSimplifiedChineseWritesAppleLanguages() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .simplifiedChinese

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "simplifiedChinese")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }

    @Test func returningToSystemClearsAppleLanguagesOverride() {
        let defaults = freshDefaults()
        defaults.set(["en"], forKey: "AppleLanguages")
        defaults.set(AppLanguagePreference.english.rawValue, forKey: AppLanguageStore.preferenceKey)
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .system

        #expect(defaults.object(forKey: "AppleLanguages") == nil)
        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "system")
    }

    @Test func bootstrapAppliesStoredPreference() {
        let defaults = freshDefaults()
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
