import Foundation
import Testing
@testable import GitRelay

@MainActor
@Suite(.serialized)
struct FeatureOwnershipControllerTests {
    @MainActor
    private struct Fixture {
        let directory: URL
        let suiteName: String
        let defaults: UserDefaults
        let library: MirrorLibraryModel
        let operations: MirrorOperationsController
        let issues: AppIssueModel

        @MainActor
        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitrelay-feature-owners-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            suiteName = "gitrelay.feature-owners.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            library = MirrorLibraryModel(
                planStore: MirrorPlanStore(fileURL: directory.appendingPathComponent("mirrors.json")),
                stateStore: MirrorStateStore(fileURL: directory.appendingPathComponent("state.json")),
                runStore: MirrorRunStore(directoryURL: directory.appendingPathComponent("logs")),
                credentialProbe: .alwaysPresent
            )
            operations = MirrorOperationsController(
                library: library,
                credentialProbe: .alwaysPresent
            )
            issues = AppIssueModel()
        }

        @MainActor
        func preferences() -> AppPreferencesModel {
            AppPreferencesModel(
                verificationStore: VerificationPreferencesStore(defaults: defaults),
                orgSubscriptionStore: OrgSubscriptionStore(defaults: defaults),
                webhookStore: WebhookPreferencesStore(defaults: defaults),
                securityStore: SecurityPreferencesStore(defaults: defaults),
                cacheStore: CachePreferencesStore(defaults: defaults),
                notificationStore: NotificationPreferencesStore(defaults: defaults),
                behaviorStore: AppBehaviorPreferencesStore(defaults: defaults)
            )
        }

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func preferencesOwnLiveVerificationAndSubscriptionProjections() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferences = fixture.preferences()
        var verification = preferences.verification
        verification.sampleSize = 7
        preferences.updateVerification(verification)
        let subscription = OrgSubscription(
            provider: .github,
            accountLabel: "default",
            organizationName: "acme"
        )
        preferences.orgSubscriptionStore.add(subscription)

        #expect(preferences.verification.sampleSize == 7)
        #expect(preferences.orgSubscriptions.map(\.id) == [subscription.id])
    }

    @Test func securityControllerOwnsSensitiveActionGate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferences = SecurityPreferencesStore(defaults: fixture.defaults)
        preferences.preferences = SecurityPreferences(requireBiometricForSensitive: true)
        let authenticator = StubBiometricAuthenticator(result: false)
        let controller = SecurityController(
            preferences: preferences,
            authenticator: authenticator
        )

        #expect(await !controller.authorize(.deleteRepository))
        #expect(authenticator.lastReason != nil)
    }

    @Test func webhookControllerOwnsListenerAndRoutingBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferences = WebhookPreferencesStore(defaults: fixture.defaults)
        preferences.preferences = .default
        let controller = WebhookController(
            library: fixture.library,
            operations: fixture.operations,
            preferences: preferences,
            issues: fixture.issues
        )
        let response = controller.handle(
            WebhookHTTPRequest(method: "GET", path: "/health", headers: [:], body: Data())
        )

        #expect(response.statusCode == 200)
        #expect(!controller.isListenerRunning)
        #expect(fixture.operations.inProgressSyncIDs.isEmpty)
    }

    @Test func cacheControllerOwnsUsageProjection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = MirrorCacheController(
            library: fixture.library,
            operations: fixture.operations,
            preferences: CachePreferencesStore(defaults: fixture.defaults),
            issues: fixture.issues
        )

        controller.refreshUsage()
        #expect(controller.usageBytes == 0)
        #expect(controller.mirrorUsages.isEmpty)
        #expect(!controller.isCleaning)
    }

    @Test func managementCommitsAndReconcilesMirrorOwners() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferences = fixture.preferences()
        let workspace = WorkspaceModel(
            library: fixture.library,
            operations: fixture.operations,
            windowLayout: WindowLayoutStore(defaults: fixture.defaults)
        )
        let scheduling = MirrorSchedulingController(
            library: fixture.library,
            operations: fixture.operations
        )
        preferences.bindScheduling(scheduling, operations: fixture.operations)
        let cache = MirrorCacheController(
            library: fixture.library,
            operations: fixture.operations,
            preferences: preferences.cacheStore,
            issues: fixture.issues
        )
        let webhooks = WebhookController(
            library: fixture.library,
            operations: fixture.operations,
            preferences: preferences.webhookStore,
            issues: fixture.issues
        )
        let notifications = NotificationController(
            library: fixture.library,
            operations: fixture.operations,
            scheduling: scheduling,
            workspace: workspace,
            cache: cache,
            preferences: preferences.notificationStore,
            issues: fixture.issues
        )
        let discovery = OrgDiscoveryController(
            library: fixture.library,
            scheduling: scheduling,
            preferences: preferences,
            notifications: notifications,
            issues: fixture.issues
        )
        let management = MirrorManagementController(
            library: fixture.library,
            operations: fixture.operations,
            scheduling: scheduling,
            workspace: workspace,
            issues: fixture.issues,
            preferences: preferences,
            cache: cache,
            webhooks: webhooks,
            notifications: notifications,
            orgDiscovery: discovery
        )
        let mirror = MirrorSnapshot(
            name: "managed",
            srcURL: "git@github.com:acme/managed.git",
            dstURL: "git@gitlab.com:acme/managed.git"
        )

        management.add(mirror)
        #expect(fixture.library.mirrors.map(\.id) == [mirror.id])
        #expect(fixture.operations.statuses[mirror.id] != nil)

        management.delete(mirrorID: mirror.id)
        #expect(fixture.library.mirrors.isEmpty)
        #expect(fixture.operations.statuses[mirror.id] == nil)
    }
}
