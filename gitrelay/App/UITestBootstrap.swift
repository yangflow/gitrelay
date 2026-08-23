#if DEBUG
import Foundation

/// Builds deterministic, isolated libraries for UI automation. It is inert in
/// normal debug launches and is not compiled into release builds.
nonisolated enum UITestBootstrap {
    static func prepareIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITRELAY_UI_TEST_MODE"] == "1",
              let basePath = environment["GITRELAY_UI_TEST_BASE"],
              !basePath.isEmpty else { return }

        let baseURL = URL(fileURLWithPath: basePath, isDirectory: true)
        Constants.setBaseDirectoryForTesting(baseURL)
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        if environment["GITRELAY_UI_TEST_RESET_DEFAULTS"] == "1" {
            UserDefaults.standard.removePersistentDomain(forName: Constants.bundleID)
        }

        switch environment["GITRELAY_UI_TEST_FIXTURE"] ?? "empty" {
        case "attention":
            seedAttentionMirror()
        case "deep-link":
            seedDeepLinkMirrors()
        case "many":
            seedManyMirrors()
        default:
            break
        }
    }

    private static func seedAttentionMirror() {
        let mirrorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let destinationID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let plan = MirrorPlan(
            id: mirrorID,
            name: "Continuity Demo",
            source: GitEndpoint(
                url: "git@github.com:example/source.git",
                provider: .github
            ),
            destinations: [
                .git(
                    id: destinationID,
                    url: "git@gitlab.com:example/mirror.git",
                    provider: .gitlab
                )
            ],
            labels: ["critical"]
        )
        let failure = MirrorFailureSummary(
            kind: .network,
            message: "The destination could not be reached.",
            failedAt: Date().addingTimeInterval(-300),
            destinationID: destinationID
        )
        let health = MirrorHealthSnapshot(
            mirrorID: mirrorID,
            lastAttemptAt: failure.failedAt,
            lastFailure: failure,
            consecutiveFailures: 2,
            destinations: [
                MirrorDestinationHealthSnapshot(
                    destinationID: destinationID,
                    lastAttemptAt: failure.failedAt,
                    lastFailure: failure
                )
            ]
        )
        try? MirrorPlanStore().save([plan])
        try? MirrorStateStore().save([mirrorID: health])
    }

    private static func seedManyMirrors() {
        let plans = (0..<200).map { index in
            MirrorPlan(
                id: UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        index + 1
                    )
                )!,
                name: String(format: "Mirror %03d", index),
                source: GitEndpoint(url: "git@github.com:example/source-\(index).git"),
                destinations: [
                    .git(url: "git@gitlab.com:example/mirror-\(index).git")
                ],
                labels: index.isMultiple(of: 2) ? ["even"] : ["odd"]
            )
        }
        try? MirrorPlanStore().save(plans)
    }

    private static func seedDeepLinkMirrors() {
        seedAttentionMirror()

        let mirrorID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let destinationID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let successDate = Date().addingTimeInterval(-60)
        let plan = MirrorPlan(
            id: mirrorID,
            name: "Healthy Destination",
            source: GitEndpoint(url: "git@github.com:example/healthy.git", provider: .github),
            destinations: [
                .git(
                    id: destinationID,
                    url: "git@gitlab.com:example/healthy-mirror.git",
                    provider: .gitlab
                )
            ]
        )
        let health = MirrorHealthSnapshot(
            mirrorID: mirrorID,
            lastAttemptAt: successDate,
            lastSuccessfulAt: successDate,
            destinations: [
                MirrorDestinationHealthSnapshot(
                    destinationID: destinationID,
                    lastAttemptAt: successDate,
                    lastSuccessfulAt: successDate
                )
            ]
        )

        let existingPlans = (try? MirrorPlanStore().load()) ?? []
        var existingHealth = (try? MirrorStateStore().load()) ?? [:]
        existingHealth[mirrorID] = health
        try? MirrorPlanStore().save(existingPlans + [plan])
        try? MirrorStateStore().save(existingHealth)
    }
}
#endif
