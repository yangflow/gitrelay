import Foundation

nonisolated enum ConfigImportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case merge
    case replace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .merge: String(localized: "Merge (skip existing IDs)")
        case .replace: String(localized: "Replace all")
        }
    }
}

nonisolated enum ConfigExportError: LocalizedError, Equatable {
    case corruptJSON
    case unsupportedRepositoryDocument
    case unsupportedFormat(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case partialDecode(String)

    var errorDescription: String? {
        switch self {
        case .corruptJSON:
            return String(localized: "The configuration file is damaged or is not valid JSON.")
        case .unsupportedRepositoryDocument:
            return String(localized: "This configuration uses an unsupported repository-list format. GitRelay imports mirror-plan configuration files.")
        case .unsupportedFormat(let format):
            return String(localized: "Unsupported configuration format: \(format).")
        case .unsupportedSchemaVersion(let found, let supported):
            return String(localized: "Unsupported configuration schema version \(found). This app supports version \(supported).")
        case .partialDecode(let detail):
            return String(localized: "The configuration file could not be fully read: \(detail)")
        }
    }
}

nonisolated struct ConfigImportPlan: Equatable, Sendable {
    var mirrors: [MirrorPlan]
    var providerAccounts: [ExportedProviderAccount]
    var orgSubscriptions: [OrgSubscription]
    var orgSubscriptionPreferences: OrgSubscriptionPreferences?
    var importedRepoCount: Int
    var skippedRepoCount: Int
}

nonisolated enum ConfigExportCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Export

    static func makeDocument(
        mirrors: [MirrorPlan],
        providerAccounts: [ExportedProviderAccount],
        orgSubscriptions: [OrgSubscription],
        orgSubscriptionPreferences: OrgSubscriptionPreferences?,
        exportedAt: Date = Date()
    ) -> ConfigExportDocument {
        ConfigExportDocument(
            format: ConfigExportDocument.formatIdentifier,
            schemaVersion: ConfigExportDocument.currentSchemaVersion,
            exportedAt: exportedAt,
            mirrors: mirrors.map(ExportedMirrorPlan.init(from:)),
            providerAccounts: providerAccounts,
            orgSubscriptions: orgSubscriptions.map(ExportedOrgSubscription.init(from:)),
            orgSubscriptionPreferences: orgSubscriptionPreferences
        )
    }

    static func encode(_ document: ConfigExportDocument) throws -> Data {
        try encoder.encode(document)
    }

    // MARK: - Decode (all-or-nothing)

    static func decode(_ data: Data) throws -> ConfigExportDocument {
        guard !data.isEmpty else { throw ConfigExportError.corruptJSON }

        // Reject non-JSON before attempting a typed decode so callers get a clear corrupt error.
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any] else {
            throw ConfigExportError.corruptJSON
        }

        let schemaVersion = envelope["schemaVersion"] as? Int
        if envelope["repos"] != nil {
            throw ConfigExportError.unsupportedRepositoryDocument
        }
        if let schemaVersion,
           schemaVersion != ConfigExportDocument.currentSchemaVersion {
            throw ConfigExportError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: ConfigExportDocument.currentSchemaVersion
            )
        }
        if let format = envelope["format"] as? String,
           format != ConfigExportDocument.formatIdentifier {
            throw ConfigExportError.unsupportedFormat(format)
        }

        let document: ConfigExportDocument
        do {
            document = try decoder.decode(ConfigExportDocument.self, from: data)
        } catch let error as DecodingError {
            throw ConfigExportError.partialDecode(Self.describe(error))
        } catch {
            throw ConfigExportError.partialDecode(error.localizedDescription)
        }

        guard document.format == ConfigExportDocument.formatIdentifier else {
            throw ConfigExportError.unsupportedFormat(document.format)
        }
        return document
    }

    // MARK: - Import planning (pure; does not write disk)

    static func planImport(
        document: ConfigExportDocument,
        mode: ConfigImportMode,
        existingMirrors: [MirrorPlan]
    ) throws -> ConfigImportPlan {
        let importedMirrors = try document.mirrors.map {
            try $0.toMirrorPlan().validated(allowMissingCredentials: true)
        }
        try validateUniqueMirrorIDs(importedMirrors)

        switch mode {
        case .replace:
            return ConfigImportPlan(
                mirrors: importedMirrors,
                providerAccounts: document.providerAccounts,
                orgSubscriptions: document.orgSubscriptions.map { $0.toOrgSubscription() },
                orgSubscriptionPreferences: document.orgSubscriptionPreferences,
                importedRepoCount: importedMirrors.count,
                skippedRepoCount: 0
            )
        case .merge:
            var merged = existingMirrors
            let existingIDs = Set(existingMirrors.map(\.id))
            var imported = 0
            var skipped = 0
            for mirror in importedMirrors {
                if existingIDs.contains(mirror.id) {
                    skipped += 1
                    continue
                }
                merged.append(mirror)
                imported += 1
            }

            return ConfigImportPlan(
                mirrors: merged,
                providerAccounts: document.providerAccounts,
                orgSubscriptions: document.orgSubscriptions.map { $0.toOrgSubscription() },
                orgSubscriptionPreferences: document.orgSubscriptionPreferences,
                importedRepoCount: imported,
                skippedRepoCount: skipped
            )
        }
    }

    /// Merges imported org subscriptions, skipping IDs that already exist.
    static func mergeSubscriptions(
        existing: [OrgSubscription],
        imported: [OrgSubscription]
    ) -> (merged: [OrgSubscription], importedCount: Int, skippedCount: Int) {
        let existingIDs = Set(existing.map(\.id))
        var merged = existing
        var importedCount = 0
        var skippedCount = 0
        for subscription in imported {
            if existingIDs.contains(subscription.id) {
                skippedCount += 1
                continue
            }
            merged.append(subscription)
            importedCount += 1
        }
        return (merged, importedCount, skippedCount)
    }

    /// Merges provider account labels: existing labels win; new labels are appended.
    static func mergeProviderAccounts(
        existing: [ExportedProviderAccount],
        imported: [ExportedProviderAccount]
    ) -> [ExportedProviderAccount] {
        var result = existing
        let keys = Set(existing.map { Self.accountKey($0) })
        for account in imported {
            let key = Self.accountKey(account)
            guard !keys.contains(key) else { continue }
            result.append(account)
        }
        return result
    }

    static func accountKey(_ account: ExportedProviderAccount) -> String {
        "\(account.provider.rawValue)|\(account.label)"
    }

    private static func validateUniqueMirrorIDs(_ mirrors: [MirrorPlan]) throws {
        var identifiers = Set<UUID>()
        for mirror in mirrors where !identifiers.insert(mirror.id).inserted {
            throw MirrorPersistenceError.duplicateMirrorID(mirror.id)
        }
    }

    /// True when serialized export JSON contains forbidden secret-bearing field names.
    static func containsForbiddenSecretFields(_ jsonUTF8: String) -> Bool {
        let lowered = jsonUTF8.lowercased()
        let forbidden = [
            "\"keychaintag\"",
            "\"token\"",
            "\"secrettoken\"",
            "\"password\"",
            "\"privatekey\"",
            "-----begin"
        ]
        return forbidden.contains { lowered.contains($0) }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return context.debugDescription
        case .keyNotFound(let key, let context):
            return "Missing key \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(_, let context):
            return context.debugDescription
        case .valueNotFound(_, let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}
