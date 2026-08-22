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
        defer { AppLocalization.resetOverride() }
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .english

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "english")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
        #expect(store.locale.identifier.hasPrefix("en"))
    }

    @Test func theNoteAppearsOnlyAfterAChange() {
        defer { AppLocalization.resetOverride() }
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        let quietAtLaunch = store.showsLaunchCatalogNote

        store.preference = .english
        let afterChange = store.showsLaunchCatalogNote

        #expect(!quietAtLaunch)
        #expect(afterChange)
    }

    @Test func switchingBackToTheLaunchLanguageClearsTheNote() {
        defer { AppLocalization.resetOverride() }
        let (defaults, _) = freshDefaults()
        defaults.set(
            AppLanguagePreference.simplifiedChinese.rawValue,
            forKey: AppLanguageStore.preferenceKey
        )
        let store = AppLanguageStore(defaults: defaults)
        let launchPreference = store.launchPreference

        store.preference = .english
        let afterChange = store.showsLaunchCatalogNote
        store.preference = .simplifiedChinese
        let afterSwitchingBack = store.showsLaunchCatalogNote

        #expect(launchPreference == .simplifiedChinese)
        #expect(afterChange)
        #expect(!afterSwitchingBack)
    }

    @Test func persistingSimplifiedChineseWritesAppleLanguages() {
        defer { AppLocalization.resetOverride() }
        let (defaults, _) = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .simplifiedChinese

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "simplifiedChinese")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }

    @Test func returningToSystemClearsAppleLanguagesOverride() {
        defer { AppLocalization.resetOverride() }
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
        defer { AppLocalization.resetOverride() }
        let (defaults, _) = freshDefaults()
        defaults.set(AppLanguagePreference.simplifiedChinese.rawValue, forKey: AppLanguageStore.preferenceKey)

        AppLanguageStore.bootstrapAppleLanguages(defaults: defaults)

        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }

    @Test func bootstrapSystemRemovesOverride() {
        defer { AppLocalization.resetOverride() }
        let (defaults, suiteName) = freshDefaults()
        defaults.set(["zh-Hans"], forKey: "AppleLanguages")

        AppLanguageStore.bootstrapAppleLanguages(defaults: defaults)

        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)
    }

    @Test func storedPreferenceSurvivesAnUnknownRawValue() {
        let (defaults, _) = freshDefaults()
        defaults.set("klingon", forKey: AppLanguageStore.preferenceKey)

        let stored = AppLanguageStore.storedPreference(defaults: defaults)
        #expect(stored == .system)
    }
}

@Suite("AppLocalization")
struct AppLocalizationTests {
    @Test func resolvesBareLanguageCodes() {
        let available = ["en", "zh-Hans", "Base"]
        #expect(AppLocalization.localizationName(for: "zh-Hans", available: available) == "zh-Hans")
        #expect(AppLocalization.localizationName(for: "en", available: available) == "en")
    }

    @Test @MainActor func stringFollowsPreferenceChanges() {
        defer { AppLocalization.resetOverride() }
        let suiteName = "gitrelay.tests.localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(AppLanguagePreference.english.rawValue, forKey: AppLanguageStore.preferenceKey)
        AppLanguageStore.bootstrapAppleLanguages(defaults: defaults)
        let store = AppLanguageStore(defaults: defaults)

        let english = String.loc("Settings")
        store.preference = .simplifiedChinese
        let chinese = String.loc("Settings")

        #expect(english == "Settings")
        #expect(chinese == "设置")
    }
}
