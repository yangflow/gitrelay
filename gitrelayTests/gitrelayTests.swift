import Foundation
import Testing
@testable import GitRelay

// MARK: - SyncFrequency

struct SyncFrequencyTests {
    @Test func manualHasNoInterval() {
        #expect(SyncFrequency.manual.interval == nil)
    }

    @Test func scheduledIntervalsAreCorrect() {
        #expect(SyncFrequency.min15.interval == 900)
        #expect(SyncFrequency.min30.interval == 1800)
        #expect(SyncFrequency.hour1.interval == 3600)
        #expect(SyncFrequency.day1.interval == 86400)
    }
}

// MARK: - String.truncatingSHA

struct TruncatingSHATests {
    @Test func truncatesToSeven() {
        #expect("abc1234def5678".truncatingSHA == "abc1234")
    }

    @Test func shortStringUnchanged() {
        #expect("abc".truncatingSHA == "abc")
    }

    @Test func exactlySevenUnchanged() {
        #expect("abc1234".truncatingSHA == "abc1234")
    }

    @Test func emptyStringUnchanged() {
        #expect("".truncatingSHA == "")
    }
}

// MARK: - Credential Redaction

struct CredentialRedactionTests {
    @Test func redactsHTTPSToken() {
        let input = "fatal: repository 'https://mytoken@github.com/user/repo.git' not found"
        let result = SyncEngine.redactCredentials(input)
        #expect(!result.contains("mytoken"))
        #expect(result.contains("https://****@"))
    }

    @Test func sshURLUnchanged() {
        let input = "git@github.com:user/repo.git"
        #expect(SyncEngine.redactCredentials(input) == input)
    }

    @Test func redactsMultipleTokens() {
        let input = "https://tok1@host1.com failed, https://tok2@host2.com rejected"
        let result = SyncEngine.redactCredentials(input)
        #expect(!result.contains("tok1"))
        #expect(!result.contains("tok2"))
        #expect(result.contains("https://****@host1.com"))
        #expect(result.contains("https://****@host2.com"))
    }

    @Test func plainMessageUnchanged() {
        let input = "Connection timed out"
        #expect(SyncEngine.redactCredentials(input) == input)
    }
}

// MARK: - DestructivePushPlan

@MainActor
struct DestructivePushPlanTests {
    @Test func parsesDeletedRefs() {
        let output = """
        To github.com:user/mirror.git
         - [deleted]         stale-branch
         - [deleted]         refs/tags/v1.0.0
        """

        let plan = DestructivePushPlan.parse(gitOutput: output)

        #expect(plan.deletedRefs == ["stale-branch", "refs/tags/v1.0.0"])
        #expect(plan.forcedUpdateRefs.isEmpty)
        #expect(plan.isDestructive)
    }

    @Test func parsesForcedUpdates() {
        let output = """
        To github.com:user/mirror.git
         + 2ab034b...394de57 main -> main (forced update)
         + 7e1a111...9aa2200 refs/tags/v1 -> refs/tags/v1 (forced update)
        """

        let plan = DestructivePushPlan.parse(gitOutput: output)

        #expect(plan.deletedRefs.isEmpty)
        #expect(plan.forcedUpdateRefs == ["main", "refs/tags/v1"])
        #expect(plan.isDestructive)
    }

    @Test func ignoresNonDestructiveDryRunLines() {
        let output = """
        To github.com:user/mirror.git
         * [new branch]      main -> main
           abc1234..def5678  develop -> develop
        """

        #expect(DestructivePushPlan.parse(gitOutput: output) == .empty)
    }
}

// MARK: - RepoConfig Codable

@MainActor
struct RepoConfigCodableTests {
    @Test func newReposDefaultToStrictDestructivePushPolicy() {
        let repo = RepoConfig(
            name: "my-repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )

        #expect(repo.destructivePushPolicy == .strict)
    }

    @Test func existingReposWithoutPolicyDecodeAsAuto() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-repo",
          "srcURL": "git@github.com:user/repo.git",
          "dstURL": "git@github.com:user/mirror.git",
          "srcAuth": { "sshAgent": {} },
          "dstAuth": { "sshAgent": {} },
          "frequency": "手动",
          "createdAt": "2026-04-25T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let repo = try decoder.decode(RepoConfig.self, from: Data(json.utf8))

        #expect(repo.destructivePushPolicy == .auto)
    }

    @Test func legacySuccessfulSyncBackfillsLastSuccessfulSyncedAt() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-repo",
          "srcURL": "git@github.com:user/repo.git",
          "dstURL": "git@github.com:user/mirror.git",
          "srcAuth": { "sshAgent": {} },
          "dstAuth": { "sshAgent": {} },
          "frequency": "手动",
          "createdAt": "2026-04-25T12:00:00Z",
          "lastSyncedAt": "2026-04-25T13:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let repo = try decoder.decode(RepoConfig.self, from: Data(json.utf8))

        #expect(repo.lastSuccessfulSyncedAt == repo.lastSyncedAt)
        #expect(repo.consecutiveFailureCount == 0)
    }

    @Test func legacyFailedSyncDefaultsToOneFailure() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-repo",
          "srcURL": "git@github.com:user/repo.git",
          "dstURL": "git@github.com:user/mirror.git",
          "srcAuth": { "sshAgent": {} },
          "dstAuth": { "sshAgent": {} },
          "frequency": "手动",
          "createdAt": "2026-04-25T12:00:00Z",
          "lastSyncedAt": "2026-04-25T13:00:00Z",
          "lastSyncError": "network failed"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let repo = try decoder.decode(RepoConfig.self, from: Data(json.utf8))

        #expect(repo.lastSuccessfulSyncedAt == nil)
        #expect(repo.consecutiveFailureCount == 1)
    }

    @Test func recordSyncResultIncrementsFailuresAndResetsOnSuccess() {
        let failureAt = Date(timeIntervalSince1970: 1_777_080_000)
        let successAt = failureAt.addingTimeInterval(60)
        var repo = RepoConfig(
            name: "my-repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )

        repo.recordSyncResult(at: failureAt, error: "network failed")
        repo.recordSyncResult(at: failureAt.addingTimeInterval(30), error: "still failing")

        #expect(repo.lastSyncedAt == failureAt.addingTimeInterval(30))
        #expect(repo.lastSuccessfulSyncedAt == nil)
        #expect(repo.lastSyncError == "still failing")
        #expect(repo.consecutiveFailureCount == 2)

        repo.recordSyncResult(at: successAt, error: nil)

        #expect(repo.lastSyncedAt == successAt)
        #expect(repo.lastSuccessfulSyncedAt == successAt)
        #expect(repo.lastSyncError == nil)
        #expect(repo.consecutiveFailureCount == 0)
    }
}

// MARK: - SyncHealthSummary

struct SyncHealthSummaryTests {
    @Test func classifiesTodaySuccessFailureAndNotRunRepos() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        let yesterday = makeDate(year: 2026, month: 4, day: 24, hour: 12, calendar: calendar)

        let successRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            lastSyncedAt: now,
            lastSuccessfulSyncedAt: now
        )
        let failedRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            lastSyncedAt: now,
            lastSyncError: "network failed",
            consecutiveFailureCount: 3
        )
        let notRunRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            lastSyncedAt: yesterday,
            lastSuccessfulSyncedAt: yesterday
        )

        let summary = SyncHealthSummary.make(
            repos: [successRepo, failedRepo, notRunRepo],
            statuses: [:],
            now: now,
            calendar: calendar
        )

        #expect(summary.succeededToday == 1)
        #expect(summary.failedToday == 1)
        #expect(summary.notRunToday == 1)
        #expect(summary.total == 3)
        #expect(summary.hasFailures)
    }

    @Test func failedStatusCountsAsTodayFailure() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        let repo = makeRepo(
            id: repoID,
            lastSyncedAt: now,
            lastSuccessfulSyncedAt: now
        )

        let summary = SyncHealthSummary.make(
            repos: [repo],
            statuses: [repoID: .failed("blocked")],
            now: now,
            calendar: calendar
        )

        #expect(summary.succeededToday == 0)
        #expect(summary.failedToday == 1)
        #expect(summary.notRunToday == 0)
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeRepo(
        id: UUID,
        lastSyncedAt: Date?,
        lastSuccessfulSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        consecutiveFailureCount: Int = 0
    ) -> RepoConfig {
        RepoConfig(
            id: id,
            name: "repo-\(id.uuidString.suffix(4))",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: lastSyncError,
            consecutiveFailureCount: consecutiveFailureCount
        )
    }
}

// MARK: - Form Validation

@MainActor
struct AddEditRepoValidationTests {
    @Test func emptyNameIsInvalid() {
        let vm = AddEditRepoViewModel()
        vm.srcURL = "git@github.com:user/repo.git"
        vm.dstURL = "git@github.com:user/mirror.git"
        _ = vm.validate()
        #expect(vm.nameError != nil)
    }

    @Test func whitespaceOnlyNameIsInvalid() {
        let vm = AddEditRepoViewModel()
        vm.name = "   "
        vm.srcURL = "git@github.com:user/repo.git"
        vm.dstURL = "git@github.com:user/mirror.git"
        _ = vm.validate()
        #expect(vm.nameError != nil)
    }

    @Test func sshURLsAreValid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "git@gitlab.com:org/repo.git"
        vm.dstURL = "git@github.com:user/repo.git"
        #expect(vm.validate())
        #expect(vm.srcError == nil)
        #expect(vm.dstError == nil)
    }

    @Test func httpsURLsAreValid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "https://github.com/user/repo.git"
        vm.dstURL = "https://github.com/user/mirror.git"
        #expect(vm.validate())
    }

    @Test func invalidURLIsRejected() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "not-a-url"
        vm.dstURL = "git@github.com:user/mirror.git"
        _ = vm.validate()
        #expect(vm.srcError != nil)
        #expect(vm.dstError == nil)
    }

    @Test func emptyURLsAreInvalid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        _ = vm.validate()
        #expect(vm.srcError != nil)
        #expect(vm.dstError != nil)
    }

    @Test func buildRepoConfigKeepsDestructivePushPolicy() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "git@gitlab.com:org/repo.git"
        vm.dstURL = "git@github.com:user/repo.git"
        vm.destructivePushPolicy = .auto

        let repo = vm.buildRepoConfig()

        #expect(repo.destructivePushPolicy == .auto)
    }

    @Test func buildRepoConfigPreservesHealthFieldsWhenEditing() {
        let lastSyncedAt = Date(timeIntervalSince1970: 1_777_080_000)
        let lastSuccessfulSyncedAt = lastSyncedAt.addingTimeInterval(-3_600)
        let existingRepo = RepoConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            name: "old-name",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: "network failed",
            consecutiveFailureCount: 4
        )
        let vm = AddEditRepoViewModel(editing: existingRepo)
        vm.name = "new-name"

        let repo = vm.buildRepoConfig()

        #expect(repo.name == "new-name")
        #expect(repo.lastSyncedAt == lastSyncedAt)
        #expect(repo.lastSuccessfulSyncedAt == lastSuccessfulSyncedAt)
        #expect(repo.lastSyncError == "network failed")
        #expect(repo.consecutiveFailureCount == 4)
    }
}

// MARK: - FailureNotificationPolicy

struct FailureNotificationPolicyTests {
    @Test func disabledNeverNotifies() {
        let policy = FailureNotificationPolicy(
            isEnabled: false,
            notifyOnFirstFailure: true,
            consecutiveFailureThreshold: 3
        )
        #expect(!policy.shouldNotify(consecutiveFailureCount: 1))
        #expect(!policy.shouldNotify(consecutiveFailureCount: 3))
        #expect(!policy.shouldNotify(consecutiveFailureCount: 6))
    }

    @Test func zeroCountNeverNotifies() {
        let policy = FailureNotificationPolicy()
        #expect(!policy.shouldNotify(consecutiveFailureCount: 0))
        #expect(!policy.shouldNotify(consecutiveFailureCount: -1))
    }

    @Test func notifiesOnFirstFailureWhenEnabled() {
        let policy = FailureNotificationPolicy(
            notifyOnFirstFailure: true,
            consecutiveFailureThreshold: 3
        )
        #expect(policy.shouldNotify(consecutiveFailureCount: 1))
        #expect(!policy.shouldNotify(consecutiveFailureCount: 2))
        #expect(policy.shouldNotify(consecutiveFailureCount: 3))
        #expect(!policy.shouldNotify(consecutiveFailureCount: 4))
        #expect(policy.shouldNotify(consecutiveFailureCount: 6))
    }

    @Test func skipsFirstFailureWhenDisabled() {
        let policy = FailureNotificationPolicy(
            notifyOnFirstFailure: false,
            consecutiveFailureThreshold: 3
        )
        #expect(!policy.shouldNotify(consecutiveFailureCount: 1))
        #expect(!policy.shouldNotify(consecutiveFailureCount: 2))
        #expect(policy.shouldNotify(consecutiveFailureCount: 3))
        #expect(policy.shouldNotify(consecutiveFailureCount: 6))
    }

    @Test func thresholdOfOneNotifiesEveryFailure() {
        let policy = FailureNotificationPolicy(
            notifyOnFirstFailure: false,
            consecutiveFailureThreshold: 1
        )
        #expect(policy.shouldNotify(consecutiveFailureCount: 1))
        #expect(policy.shouldNotify(consecutiveFailureCount: 2))
        #expect(policy.shouldNotify(consecutiveFailureCount: 5))
    }

    @Test func clampsNonPositiveThresholdToOne() {
        let policy = FailureNotificationPolicy(consecutiveFailureThreshold: 0)
        #expect(policy.consecutiveFailureThreshold == 1)
        #expect(policy.shouldNotify(consecutiveFailureCount: 1))
    }
}

// MARK: - FailureNotificationCopy

struct FailureNotificationCopyTests {
    @Test func singleFailureBodyOmitsStreakPrefix() {
        #expect(
            FailureNotificationCopy.body(message: "Network error", consecutiveFailureCount: 1)
            == "Network error"
        )
    }

    @Test func streakBodyIncludesCount() {
        #expect(
            FailureNotificationCopy.body(message: "Network error", consecutiveFailureCount: 4)
            == "连续失败 4 次 — Network error"
        )
    }

    @Test func aggregatedBodyListsRepoNames() {
        let body = FailureNotificationCopy.aggregatedBody(
            items: [
                (repoName: "alpha", message: "fail", count: 2),
                (repoName: "beta", message: "fail", count: 3),
                (repoName: "gamma", message: "fail", count: 1),
                (repoName: "delta", message: "fail", count: 1)
            ]
        )
        #expect(body.contains("4 个仓库同步失败"))
        #expect(body.contains("alpha"))
        #expect(body.contains("beta"))
        #expect(body.contains("gamma"))
        #expect(body.contains("等"))
    }

    @Test func aggregatedBodyForSingleItemUsesRepoDetail() {
        let body = FailureNotificationCopy.aggregatedBody(
            items: [(repoName: "alpha", message: "Network error", count: 2)]
        )
        #expect(body.contains("alpha"))
        #expect(body.contains("Network error"))
        #expect(body.contains("连续失败 2 次"))
    }
}

// MARK: - SyncPausePolicy

struct SyncPausePolicyTests {
    @Test func pausesOnlyWhenMatchingFlagsEnabled() {
        let policy = SyncPausePolicy(pauseOnLowPowerMode: true, pauseOnExpensiveNetwork: true)
        #expect(policy.shouldPause(isLowPowerMode: true, isExpensiveNetwork: false))
        #expect(policy.shouldPause(isLowPowerMode: false, isExpensiveNetwork: true))
        #expect(policy.shouldPause(isLowPowerMode: true, isExpensiveNetwork: true))
        #expect(!policy.shouldPause(isLowPowerMode: false, isExpensiveNetwork: false))
    }

    @Test func respectsDisabledPauseOptions() {
        let policy = SyncPausePolicy(pauseOnLowPowerMode: false, pauseOnExpensiveNetwork: false)
        #expect(!policy.shouldPause(isLowPowerMode: true, isExpensiveNetwork: true))
        #expect(policy.pauseReason(isLowPowerMode: true, isExpensiveNetwork: true) == nil)
    }

    @Test func reportsCombinedReason() {
        let policy = SyncPausePolicy(pauseOnLowPowerMode: true, pauseOnExpensiveNetwork: true)
        #expect(
            policy.pauseReason(isLowPowerMode: true, isExpensiveNetwork: true)
            == .lowPowerAndExpensiveNetwork
        )
        #expect(
            policy.pauseReason(isLowPowerMode: true, isExpensiveNetwork: false)
            == .lowPowerMode
        )
        #expect(
            policy.pauseReason(isLowPowerMode: false, isExpensiveNetwork: true)
            == .expensiveNetwork
        )
    }
}

// MARK: - NotificationPreferencesStore

@MainActor
struct NotificationPreferencesStoreTests {
    @Test func loadsDefaultsWhenKeysMissing() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        #expect(store.preferences == .default)
    }

    @Test func persistsAndReloadsMutations() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.notificationsEnabled = false
        prefs.notifyOnFirstFailure = false
        prefs.consecutiveFailureThreshold = 5
        prefs.interruptionLevel = .timeSensitive
        prefs.pauseOnLowPowerMode = false
        prefs.pauseOnExpensiveNetwork = false
        store.preferences = prefs

        let reloaded = NotificationPreferencesStore(defaults: defaults)
        #expect(reloaded.preferences.notificationsEnabled == false)
        #expect(reloaded.preferences.notifyOnFirstFailure == false)
        #expect(reloaded.preferences.consecutiveFailureThreshold == 5)
        #expect(reloaded.preferences.interruptionLevel == .timeSensitive)
        #expect(reloaded.preferences.pauseOnLowPowerMode == false)
        #expect(reloaded.preferences.pauseOnExpensiveNetwork == false)
    }

    @Test func resetToDefaultsRestoresFactoryValues() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.notificationsEnabled = false
        prefs.consecutiveFailureThreshold = 9
        store.preferences = prefs
        store.resetToDefaults()
        #expect(store.preferences == .default)
    }

    @Test func normalizesNonPositiveThreshold() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.consecutiveFailureThreshold = 0
        store.preferences = prefs
        #expect(store.preferences.consecutiveFailureThreshold == 1)
    }
}

// MARK: - SyncFailureNotifier (Focus deferral)

@MainActor
struct SyncFailureNotifierFocusTests {
    @Test func queuesWhileFocusedAndFlushesAfterFocusEnds() {
        var focused: Bool? = true
        let notifier = SyncFailureNotifier(focusStatusProvider: { focused })
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!

        notifier.handleSyncFailure(
            repoID: repoID,
            repoName: "demo",
            message: "Network error — check connectivity",
            consecutiveFailureCount: 1,
            preferences: .default
        )

        #expect(notifier.pendingDuringFocus[repoID]?.repoName == "demo")

        focused = false
        notifier.flushPendingIfFocusEnded(level: .active)
        #expect(notifier.pendingDuringFocus.isEmpty)
    }

    @Test func ignoresCancelledSyncFailures() {
        var focused: Bool? = true
        let notifier = SyncFailureNotifier(focusStatusProvider: { focused })
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!

        notifier.handleSyncFailure(
            repoID: repoID,
            repoName: "demo",
            message: "Cancelled",
            consecutiveFailureCount: 1,
            preferences: .default
        )

        #expect(notifier.pendingDuringFocus.isEmpty)
    }

    @Test func clearPendingDropsDeferredAlert() {
        var focused: Bool? = true
        let notifier = SyncFailureNotifier(focusStatusProvider: { focused })
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!

        notifier.handleSyncFailure(
            repoID: repoID,
            repoName: "demo",
            message: "Network error",
            consecutiveFailureCount: 1,
            preferences: .default
        )
        notifier.clearPending(for: repoID)
        #expect(notifier.pendingDuringFocus.isEmpty)
    }

    @Test func respectsDisabledNotifications() {
        var focused: Bool? = true
        let notifier = SyncFailureNotifier(focusStatusProvider: { focused })
        var prefs = NotificationPreferences.default
        prefs.notificationsEnabled = false

        notifier.handleSyncFailure(
            repoID: UUID(),
            repoName: "demo",
            message: "Network error",
            consecutiveFailureCount: 1,
            preferences: prefs
        )

        #expect(notifier.pendingDuringFocus.isEmpty)
    }
}
