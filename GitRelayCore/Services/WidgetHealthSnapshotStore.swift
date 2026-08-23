import Foundation
import Security

enum WidgetHealthSnapshotStore {
    static let appGroupID = "group.com.yangflow.gitrelay"
    static let snapshotFileName = "widget-health-snapshot.json"

    private static var testingContainerURL: URL?

    static var containerURL: URL? {
        if let testingContainerURL {
            return testingContainerURL
        }
        return authorizedContainerURL(
            applicationGroups: signedApplicationGroups,
            resolver: { groupID in
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: groupID
                )
            }
        )
    }

    /// Resolving an App Group container without the matching entitlement makes
    /// macOS treat the request as access to another app's data. Local ad-hoc
    /// builds do not carry restricted entitlements, so skip the resolver before
    /// the system can show a privacy prompt.
    static func authorizedContainerURL(
        applicationGroups: [String]?,
        resolver: (String) -> URL?
    ) -> URL? {
        guard applicationGroups?.contains(appGroupID) == true else {
            return nil
        }
        return resolver(appGroupID)
    }

    private static var signedApplicationGroups: [String]? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.security.application-groups" as CFString,
                  nil
              ) else {
            return nil
        }
        return value as? [String]
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func write(_ snapshot: WidgetHealthSnapshot) throws {
        guard let url = snapshotURL else {
            throw WidgetHealthSnapshotStoreError.containerUnavailable
        }
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    static func read() -> WidgetHealthSnapshot? {
        guard let url = snapshotURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(WidgetHealthSnapshot.self, from: data)
    }

    #if DEBUG
    static func setContainerURLForTesting(_ url: URL?) {
        testingContainerURL = url
    }
    #endif
}

enum WidgetHealthSnapshotStoreError: Error, Equatable {
    case containerUnavailable
}
