import Foundation

struct ProviderAccountRecord: Codable, Hashable, Sendable {
    var label: String
    var host: String?
}

enum ProviderAccountStore {
    private enum Keys {
        static let registry = "ProviderAccounts.registry"
        static let selectedPrefix = "ProviderAccounts.selected."
        static let migrationDone = "ProviderAccounts.legacyMigrationDone"
        static let legacyGitLabHost = "BrowseRemoteRepo.gitlabHost"
        static let legacyGiteaHost = "BrowseRemoteRepo.giteaHost"
    }

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Keys.migrationDone) else { return }

        for provider in GitProvider.allCases {
            ProviderTokenStore.migrateLegacyTokenIfNeeded(for: provider)
            ensureDefaultAccount(for: provider, defaults: defaults)
        }

        migrateLegacyHosts(defaults: defaults)

        defaults.set(true, forKey: Keys.migrationDone)
    }

    static func accounts(for provider: GitProvider, defaults: UserDefaults = .standard) -> [ProviderAccountRecord] {
        migrateIfNeeded(defaults: defaults)
        let registry = loadRegistry(defaults: defaults)
        return registry[provider.rawValue] ?? [ProviderAccountRecord(label: ProviderAccount.defaultLabel, host: nil)]
    }

    static func accountLabels(for provider: GitProvider, defaults: UserDefaults = .standard) -> [String] {
        accounts(for: provider, defaults: defaults).map(\.label)
    }

    static func selectedLabel(for provider: GitProvider, defaults: UserDefaults = .standard) -> String {
        migrateIfNeeded(defaults: defaults)
        let key = Keys.selectedPrefix + provider.rawValue
        let labels = accountLabels(for: provider, defaults: defaults)
        if let stored = defaults.string(forKey: key), labels.contains(stored) {
            return stored
        }
        return labels.first ?? ProviderAccount.defaultLabel
    }

    static func setSelectedLabel(_ label: String, for provider: GitProvider, defaults: UserDefaults = .standard) {
        migrateIfNeeded(defaults: defaults)
        defaults.set(label, forKey: Keys.selectedPrefix + provider.rawValue)
    }

    static func host(for provider: GitProvider, label: String, defaults: UserDefaults = .standard) -> String? {
        accounts(for: provider, defaults: defaults)
            .first(where: { $0.label == label })?
            .host
    }

    static func setHost(_ host: String?, for provider: GitProvider, label: String, defaults: UserDefaults = .standard) {
        migrateIfNeeded(defaults: defaults)
        setHostUnchecked(host, for: provider, label: label, defaults: defaults)
    }

    @discardableResult
    static func addAccount(
        label: String,
        for provider: GitProvider,
        defaults: UserDefaults = .standard
    ) throws -> ProviderAccountRecord {
        migrateIfNeeded(defaults: defaults)
        guard let normalized = ProviderAccount.normalizeLabel(label) else {
            throw ProviderAccountStoreError.invalidLabel
        }

        var registry = loadRegistry(defaults: defaults)
        var records = registry[provider.rawValue] ?? [ProviderAccountRecord(label: ProviderAccount.defaultLabel, host: nil)]
        guard !records.contains(where: { $0.label == normalized }) else {
            throw ProviderAccountStoreError.duplicateLabel
        }

        let record = ProviderAccountRecord(label: normalized, host: nil)
        records.append(record)
        registry[provider.rawValue] = records
        saveRegistry(registry, defaults: defaults)
        return record
    }

    static func removeAccount(
        label: String,
        for provider: GitProvider,
        defaults: UserDefaults = .standard
    ) throws {
        migrateIfNeeded(defaults: defaults)
        var registry = loadRegistry(defaults: defaults)
        var records = registry[provider.rawValue] ?? [ProviderAccountRecord(label: ProviderAccount.defaultLabel, host: nil)]
        guard records.count > 1 else { throw ProviderAccountStoreError.cannotDeleteLastAccount }
        guard records.contains(where: { $0.label == label }) else { throw ProviderAccountStoreError.accountNotFound }

        records.removeAll { $0.label == label }
        registry[provider.rawValue] = records
        saveRegistry(registry, defaults: defaults)

        ProviderTokenStore.delete(provider: provider, accountLabel: label)

        let selected = selectedLabel(for: provider, defaults: defaults)
        if selected == label {
            let next = BrowseRemoteAccountSelection.selectedLabelAfterDelete(
                deleted: label,
                current: selected,
                remaining: records.map(\.label)
            )
            setSelectedLabel(next, for: provider, defaults: defaults)
        }
    }

    // MARK: - Private

    private static func ensureDefaultAccount(for provider: GitProvider, defaults: UserDefaults) {
        var registry = loadRegistry(defaults: defaults)
        var records = registry[provider.rawValue] ?? []
        if records.isEmpty {
            records = [ProviderAccountRecord(label: ProviderAccount.defaultLabel, host: nil)]
            registry[provider.rawValue] = records
            saveRegistry(registry, defaults: defaults)
        }
    }

    private static func migrateLegacyHosts(defaults: UserDefaults) {
        if let gitlabHost = defaults.string(forKey: Keys.legacyGitLabHost), !gitlabHost.isEmpty {
            setHostUnchecked(gitlabHost, for: .gitlab, label: ProviderAccount.defaultLabel, defaults: defaults)
            defaults.removeObject(forKey: Keys.legacyGitLabHost)
        }
        if let giteaHost = defaults.string(forKey: Keys.legacyGiteaHost), !giteaHost.isEmpty {
            setHostUnchecked(giteaHost, for: .gitea, label: ProviderAccount.defaultLabel, defaults: defaults)
            defaults.removeObject(forKey: Keys.legacyGiteaHost)
        }
    }

    private static func setHostUnchecked(
        _ host: String?,
        for provider: GitProvider,
        label: String,
        defaults: UserDefaults
    ) {
        var registry = loadRegistry(defaults: defaults)
        var records = registry[provider.rawValue] ?? [ProviderAccountRecord(label: ProviderAccount.defaultLabel, host: nil)]
        guard let index = records.firstIndex(where: { $0.label == label }) else { return }

        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].host = trimmed?.isEmpty == false ? trimmed : nil
        registry[provider.rawValue] = records
        saveRegistry(registry, defaults: defaults)
    }

    private static func loadRegistry(defaults: UserDefaults) -> [String: [ProviderAccountRecord]] {
        guard let data = defaults.data(forKey: Keys.registry),
              let decoded = try? JSONDecoder().decode([String: [ProviderAccountRecord]].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveRegistry(_ registry: [String: [ProviderAccountRecord]], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(registry) {
            defaults.set(data, forKey: Keys.registry)
        }
    }
}

enum ProviderAccountStoreError: LocalizedError {
    case invalidLabel
    case duplicateLabel
    case cannotDeleteLastAccount
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .invalidLabel:
            return String(localized: "Account name must be 1–32 letters, numbers, spaces, hyphens, or underscores.")
        case .duplicateLabel:
            return String(localized: "An account with this name already exists.")
        case .cannotDeleteLastAccount:
            return String(localized: "At least one account must remain.")
        case .accountNotFound:
            return String(localized: "Account not found.")
        }
    }
}
