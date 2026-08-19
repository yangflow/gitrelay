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

    @Test func confirmationPromptMatchesIssueCopy() {
        let plan = DestructivePushPlan(
            deletedRefs: ["stale-branch", "refs/tags/v1.0.0"],
            forcedUpdateRefs: ["main"]
        )

        #expect(plan.confirmationPrompt == "本次将删除 2 个 ref / 强制更新 1 个 ref,是否继续?")
    }

    @Test func parsesMixedDestructiveDryRunOutput() {
        let output = """
        To github.com:user/mirror.git
         - [deleted]         old-feature
         + abc1234...def5678 main -> main (forced update)
           111aaaa..222bbbb  develop -> develop
         * [new tag]         v2.0.0 -> v2.0.0
        """

        let plan = DestructivePushPlan.parse(gitOutput: output)

        #expect(plan.deletedRefs == ["old-feature"])
        #expect(plan.forcedUpdateRefs == ["main"])
        #expect(plan.isDestructive)
    }
}

// MARK: - DestructivePushPolicy

struct DestructivePushPolicyTests {
    @Test func strictRequiresConfirmationOnlyWhenDestructive() {
        let destructive = DestructivePushPlan(
            deletedRefs: ["gone"],
            forcedUpdateRefs: []
        )

        #expect(DestructivePushPolicy.strict.requiresConfirmation(for: destructive))
        #expect(!DestructivePushPolicy.strict.requiresConfirmation(for: .empty))
        #expect(!DestructivePushPolicy.auto.requiresConfirmation(for: destructive))
        #expect(!DestructivePushPolicy.auto.requiresConfirmation(for: .empty))
    }

    @Test func forceOnlyPlanIsDestructiveUnderStrict() {
        let plan = DestructivePushPlan(deletedRefs: [], forcedUpdateRefs: ["main"])
        #expect(plan.isDestructive)
        #expect(DestructivePushPolicy.strict.requiresConfirmation(for: plan))
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

    @Test func legacyDstURLMigratesToTargetsOnDecode() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-repo",
          "srcURL": "git@github.com:user/repo.git",
          "dstURL": "git@github.com:user/mirror.git",
          "srcAuth": { "sshAgent": {} },
          "dstAuth": { "httpsToken": { "keychainTag": "00000000-0000-0000-0000-000000000001-dst" } },
          "frequency": "手动",
          "createdAt": "2026-04-25T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let repo = try decoder.decode(RepoConfig.self, from: Data(json.utf8))

        #expect(repo.targets.count == 1)
        #expect(repo.targets[0].url == "git@github.com:user/mirror.git")
        #expect(repo.targets[0].enabled)
        if case .httpsToken(let tag) = repo.targets[0].auth {
            #expect(tag == "00000000-0000-0000-0000-000000000001-dst")
        } else {
            Issue.record("expected migrated https token auth")
        }
    }

    @Test func encodesTargetsNotLegacyDstFields() throws {
        let repo = RepoConfig(
            name: "multi",
            srcURL: "git@github.com:user/repo.git",
            targets: [
                MirrorTarget(url: "git@github.com:user/a.git"),
                MirrorTarget(url: "git@gitlab.com:user/b.git", enabled: false)
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(repo)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(object["targets"] != nil)
        #expect(object["dstURL"] == nil)
        #expect(object["dstAuth"] == nil)
    }

    @Test func tagsDefaultToEmptyArrayOnDecode() throws {
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

        #expect(repo.tags.isEmpty)
    }

    @Test func encodesAndDecodesTags() throws {
        let repo = RepoConfig(
            name: "tagged",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            tags: ["work", "oss"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(repo)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RepoConfig.self, from: data)

        #expect(decoded.tags == ["work", "oss"])
    }

    @Test func decodeNormalizesWhitespaceAndDedupesTags() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "tagged",
          "srcURL": "git@github.com:user/repo.git",
          "targets": [{ "url": "git@github.com:user/mirror.git", "auth": { "sshAgent": {} } }],
          "srcAuth": { "sshAgent": {} },
          "frequency": "手动",
          "createdAt": "2026-04-25T12:00:00Z",
          "tags": [" work ", "work", "  ", "oss"]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let repo = try decoder.decode(RepoConfig.self, from: Data(json.utf8))

        #expect(repo.tags == ["work", "oss"])
    }
}

// MARK: - RepoTagGrouping

struct RepoTagGroupingTests {
    private func makeRepo(name: String, tags: [String] = []) -> RepoConfig {
        RepoConfig(
            name: name,
            srcURL: "git@github.com:user/\(name).git",
            dstURL: "git@github.com:user/\(name)-mirror.git",
            tags: tags
        )
    }

    @Test func allUniqueTagsAreSorted() {
        let repos = [
            makeRepo(name: "a", tags: ["work", "client"]),
            makeRepo(name: "b", tags: ["oss"])
        ]

        #expect(RepoTagGrouping.allUniqueTags(from: repos) == ["client", "oss", "work"])
    }

    @Test func sectionsIncludeUntaggedBucket() {
        let repos = [
            makeRepo(name: "tagged", tags: ["work"]),
            makeRepo(name: "plain")
        ]

        let sections = RepoTagGrouping.sections(from: repos)

        #expect(sections.count == 2)
        #expect(sections[0].title == "work")
        #expect(sections[0].repos.map(\.name) == ["tagged"])
        #expect(sections[1].title == "未标记")
        #expect(sections[1].repos.map(\.name) == ["plain"])
        #expect(sections[1].tag == nil)
    }

    @Test func multiTagRepoAppearsInMultipleSections() {
        let repos = [makeRepo(name: "shared", tags: ["work", "oss"])]

        let sections = RepoTagGrouping.sections(from: repos)

        #expect(sections.count == 2)
        #expect(sections.allSatisfy { $0.repos.count == 1 })
        #expect(sections.map(\.title).sorted() == ["oss", "work"])
    }

    @Test func repoIDsMatchingTagTargetsOnlyGroupMembers() {
        let work = makeRepo(name: "work-repo", tags: ["work"])
        let oss = makeRepo(name: "oss-repo", tags: ["oss"])
        let plain = makeRepo(name: "plain")
        let repos = [work, oss, plain]

        #expect(RepoTagGrouping.repoIDs(matching: "work", in: repos) == [work.id])
        #expect(RepoTagGrouping.repoIDs(matching: nil, in: repos) == [plain.id])
    }

    @Test func matchingSuggestionsFiltersSelectedAndPrefix() {
        let suggestions = RepoTagGrouping.matchingSuggestions(
            prefix: "wo",
            existing: ["work", "oss", "world"],
            selected: ["work"]
        )

        #expect(suggestions == ["world"])
    }
}

// MARK: - AppViewModel tag batch ops

@MainActor
struct AppViewModelTagBatchTests {
    private func makeViewModel() -> AppViewModel {
        let suite = "gitrelay.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return AppViewModel(verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults))
    }

    @Test func updateFrequencyAppliesOnlyToMatchingTag() {
        let vm = makeViewModel()
        let work = RepoConfig(
            name: "work-repo",
            srcURL: "git@github.com:user/work.git",
            dstURL: "git@github.com:user/work-mirror.git",
            frequency: .manual,
            tags: ["work"]
        )
        let oss = RepoConfig(
            name: "oss-repo",
            srcURL: "git@github.com:user/oss.git",
            dstURL: "git@github.com:user/oss-mirror.git",
            frequency: .manual,
            tags: ["oss"]
        )
        vm.addRepo(work)
        vm.addRepo(oss)

        vm.updateFrequency(matchingTag: "work", frequency: .hour1)

        #expect(vm.repos.first(where: { $0.name == "work-repo" })?.frequency == .hour1)
        #expect(vm.repos.first(where: { $0.name == "oss-repo" })?.frequency == .manual)
    }

    @Test func reposMatchingTagReturnsUntaggedBucket() {
        let vm = makeViewModel()
        vm.addRepo(RepoConfig(
            name: "plain",
            srcURL: "git@github.com:user/plain.git",
            dstURL: "git@github.com:user/plain-mirror.git"
        ))
        vm.addRepo(RepoConfig(
            name: "tagged",
            srcURL: "git@github.com:user/tagged.git",
            dstURL: "git@github.com:user/tagged-mirror.git",
            tags: ["work"]
        ))

        #expect(vm.repos(matchingTag: nil).map(\.name) == ["plain"])
        #expect(vm.repos(matchingTag: "work").map(\.name) == ["tagged"])
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

// MARK: - RepoRowHealthPresentation

struct RepoRowHealthPresentationTests {
    @Test func captionUsesLastSyncTimeAndMarksStaleAfterThreshold() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        let recentSuccess = now.addingTimeInterval(-3_600)
        let staleSuccess = now.addingTimeInterval(-90_000)

        let freshRepo = makeRepo(
            lastSyncedAt: recentSuccess,
            lastSuccessfulSyncedAt: recentSuccess
        )
        let staleRepo = makeRepo(
            lastSyncedAt: staleSuccess,
            lastSuccessfulSyncedAt: staleSuccess
        )
        let neverSyncedRepo = makeRepo(lastSyncedAt: nil, lastSuccessfulSyncedAt: nil)

        let freshCaption = RepoRowHealthPresentation.caption(
            for: freshRepo,
            status: .idle,
            now: now
        )
        let staleCaption = RepoRowHealthPresentation.caption(
            for: staleRepo,
            status: .idle,
            now: now
        )
        let neverSyncedCaption = RepoRowHealthPresentation.caption(
            for: neverSyncedRepo,
            status: .unknown,
            now: now
        )

        if case .lastSync(let date) = freshCaption.kind {
            #expect(date == recentSuccess)
        } else {
            Issue.record("Expected lastSync caption for fresh repo")
        }
        #expect(!freshCaption.isStale)

        if case .lastSync(let date) = staleCaption.kind {
            #expect(date == staleSuccess)
        } else {
            Issue.record("Expected lastSync caption for stale repo")
        }
        #expect(staleCaption.isStale)
        #expect(neverSyncedCaption.kind == .neverSynced)
        #expect(neverSyncedCaption.isStale)
    }

    @Test func divergedStatusOverridesSyncCaption() {
        let now = Date(timeIntervalSince1970: 1_777_080_000)
        let repo = makeRepo(
            lastSyncedAt: now,
            lastSuccessfulSyncedAt: now
        )

        let caption = RepoRowHealthPresentation.caption(
            for: repo,
            status: .diverged("tree mismatch"),
            now: now.addingTimeInterval(60)
        )

        #expect(caption.kind == .diverged)
    }

    @Test func failureBadgeAppearsFromThirdConsecutiveFailure() {
        let repoBelowThreshold = makeRepo(consecutiveFailureCount: 2)
        let repoAtThreshold = makeRepo(consecutiveFailureCount: 3)
        let repoAboveThreshold = makeRepo(consecutiveFailureCount: 5)

        #expect(!RepoRowHealthPresentation.showsFailureBadge(for: repoBelowThreshold))
        #expect(RepoRowHealthPresentation.failureBadgeCount(for: repoBelowThreshold) == nil)

        #expect(RepoRowHealthPresentation.showsFailureBadge(for: repoAtThreshold))
        #expect(RepoRowHealthPresentation.failureBadgeCount(for: repoAtThreshold) == 3)

        #expect(RepoRowHealthPresentation.showsFailureBadge(for: repoAboveThreshold))
        #expect(RepoRowHealthPresentation.failureBadgeCount(for: repoAboveThreshold) == 5)
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
        lastSyncedAt: Date?,
        lastSuccessfulSyncedAt: Date? = nil,
        consecutiveFailureCount: Int = 0
    ) -> RepoConfig {
        RepoConfig(
            name: "repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            consecutiveFailureCount: consecutiveFailureCount
        )
    }
}

// MARK: - SyncHistorySparkline

struct SyncHistorySparklineTests {
    @Test func buildsThirtyDaySeriesWithZeroFilledDays() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        let todayKey = SyncHistorySparkline.dayKey(for: now, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let yesterdayKey = SyncHistorySparkline.dayKey(for: yesterday, calendar: calendar)

        let sparkline = SyncHistorySparkline.make(
            from: [
                todayKey: SyncDayOutcome(successes: 2, failures: 1),
                yesterdayKey: SyncDayOutcome(successes: 1, failures: 0),
            ],
            now: now,
            calendar: calendar
        )

        #expect(sparkline.days.count == 30)
        #expect(sparkline.days.last?.successes == 2)
        #expect(sparkline.days.last?.failures == 1)
        #expect(sparkline.days[sparkline.days.count - 2].successes == 1)
        #expect(sparkline.days[sparkline.days.count - 2].failures == 0)
        #expect(sparkline.days.first?.total == 0)
    }

    @Test func recordSyncResultPersistsDailyOutcomesAndPrunesOldEntries() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        var repo = RepoConfig(
            name: "repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )

        repo.recordSyncResult(at: now, error: nil, calendar: calendar)
        repo.recordSyncResult(at: now.addingTimeInterval(60), error: "network failed", calendar: calendar)

        let todayKey = SyncHistorySparkline.dayKey(for: now, calendar: calendar)
        #expect(repo.dailySyncOutcomes[todayKey] == SyncDayOutcome(successes: 1, failures: 1))

        let oldDate = calendar.date(byAdding: .day, value: -40, to: now)!
        let oldKey = SyncHistorySparkline.dayKey(for: oldDate, calendar: calendar)
        repo.dailySyncOutcomes[oldKey] = SyncDayOutcome(successes: 9, failures: 0)
        repo.recordSyncResult(at: now.addingTimeInterval(120), error: nil, calendar: calendar)

        #expect(repo.dailySyncOutcomes[oldKey] == nil)
        #expect(repo.dailySyncOutcomes[todayKey] == SyncDayOutcome(successes: 2, failures: 1))
    }

    @Test func aggregatesRecordsIntoDailyBuckets() {
        let calendar = makeUTCCalendar()
        let day = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)

        let successRecord = makeRecord(
            startedAt: day.addingTimeInterval(-600),
            finishedAt: day.addingTimeInterval(-500),
            succeeded: true
        )
        let failureRecord = makeRecord(
            startedAt: day.addingTimeInterval(-300),
            finishedAt: day.addingTimeInterval(-200),
            succeeded: false
        )

        let sparkline = SyncHistorySparkline.make(
            from: [successRecord, failureRecord],
            now: day,
            calendar: calendar,
            dayCount: 1
        )

        #expect(sparkline.days.count == 1)
        #expect(sparkline.days[0].successes == 1)
        #expect(sparkline.days[0].failures == 1)
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

    private func makeRecord(
        startedAt: Date,
        finishedAt: Date,
        succeeded: Bool
    ) -> SyncRecord {
        SyncRecord(
            repoID: UUID(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            succeeded: succeeded
        )
    }
}

// MARK: - VerificationDecision

struct VerificationDecisionTests {
    @Test func identicalCommitSHAsMatchWithoutTrees() {
        let decision = VerificationDecision.decide(
            branch: "main",
            srcCommitSHA: "aaa111",
            dstCommitSHA: "aaa111"
        )
        #expect(decision == .matched(reason: .identicalCommitSHA))
    }

    @Test func differingSHAsWithIdenticalTreesMatch() {
        let decision = VerificationDecision.decide(
            branch: "main",
            srcCommitSHA: "aaa111",
            dstCommitSHA: "bbb222",
            srcTreeHash: "tree999",
            dstTreeHash: "tree999"
        )
        #expect(decision == .matched(reason: .identicalTreeHash))
    }

    @Test func differingSHAsAndTreesMarkDiverged() {
        let decision = VerificationDecision.decide(
            branch: "main",
            srcCommitSHA: "aaa111",
            dstCommitSHA: "bbb222",
            srcTreeHash: "treeSRC",
            dstTreeHash: "treeDST"
        )
        guard case .diverged(let detail) = decision else {
            Issue.record("expected diverged")
            return
        }
        #expect(detail.srcCommitSHA == "aaa111")
        #expect(detail.dstCommitSHA == "bbb222")
        #expect(detail.srcTreeHash == "treeSRC")
        #expect(detail.dstTreeHash == "treeDST")
        #expect(detail.summary.contains("main"))
    }

    @Test func missingDstRefIsInconclusive() {
        let decision = VerificationDecision.decide(
            branch: "main",
            srcCommitSHA: "aaa111",
            dstCommitSHA: nil
        )
        guard case .inconclusive(let message) = decision else {
            Issue.record("expected inconclusive")
            return
        }
        #expect(message.contains("目标"))
    }

    @Test func differingSHAsWithoutTreesAreInconclusive() {
        let decision = VerificationDecision.decide(
            branch: "main",
            srcCommitSHA: "aaa111",
            dstCommitSHA: "bbb222"
        )
        guard case .inconclusive = decision else {
            Issue.record("expected inconclusive when trees are missing")
            return
        }
    }
}

// MARK: - VerificationSampler

struct VerificationSamplerTests {
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1
            return state
        }
    }

    @Test func sampleRespectsCountAndDoesNotExceedPopulation() {
        let repos = (0..<5).map { index in
            RepoConfig(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
                name: "repo-\(index)",
                srcURL: "git@github.com:user/repo.git",
                dstURL: "git@github.com:user/mirror.git"
            )
        }
        var generator = SeededGenerator(state: 42)
        let sample = VerificationSampler.sample(from: repos, count: 3, using: &generator)
        #expect(sample.count == 3)
        #expect(Set(sample.map(\.id)).count == 3)
    }

    @Test func sampleOfZeroOrEmptyIsEmpty() {
        #expect(VerificationSampler.sample(from: [], count: 3).isEmpty)
        let repo = RepoConfig(
            name: "only",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )
        var generator = SeededGenerator(state: 7)
        #expect(VerificationSampler.sample(from: [repo], count: 0, using: &generator).isEmpty)
    }

    @Test func sampleCountLargerThanPopulationReturnsAll() {
        let repos = (0..<2).map { index in
            RepoConfig(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000001\(index)")!,
                name: "repo-\(index)",
                srcURL: "git@github.com:user/repo.git",
                dstURL: "git@github.com:user/mirror.git"
            )
        }
        var generator = SeededGenerator(state: 99)
        let sample = VerificationSampler.sample(from: repos, count: 10, using: &generator)
        #expect(sample.count == 2)
    }
}

// MARK: - GitRunner ls-remote parsing

struct LSRemoteParsingTests {
    @Test func parsesMatchingRef() {
        let output = """
        abcdef0123456789\trefs/heads/main
        1111222233334444\trefs/heads/develop
        """
        #expect(GitRunner.parseLSRemoteSHA(output, matchingRef: "refs/heads/main") == "abcdef0123456789")
        #expect(GitRunner.parseLSRemoteSHA(output, matchingRef: "refs/heads/develop") == "1111222233334444")
    }

    @Test func missingRefReturnsNil() {
        let output = "abcdef0123456789\trefs/heads/main\n"
        #expect(GitRunner.parseLSRemoteSHA(output, matchingRef: "refs/heads/other") == nil)
    }
}

// MARK: - Diverged persistence

struct DivergedStateTests {
    @Test func recordVerificationResultSetsAndClearsDivergence() {
        var repo = RepoConfig(
            name: "my-repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )
        let verifiedAt = Date(timeIntervalSince1970: 1_777_100_000)

        repo.recordVerificationResult(at: verifiedAt, divergedDetail: "分支 main 内容分歧")
        #expect(repo.isDiverged)
        #expect(repo.lastVerifiedAt == verifiedAt)
        #expect(repo.divergedDetail == "分支 main 内容分歧")

        repo.recordVerificationResult(at: verifiedAt.addingTimeInterval(60), divergedDetail: nil)
        #expect(!repo.isDiverged)
        #expect(repo.divergedDetail == nil)
    }

    @Test func successfulSyncClearsDivergence() {
        var repo = RepoConfig(
            name: "my-repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            divergedDetail: "旧分歧"
        )
        repo.recordSyncResult(error: nil)
        #expect(repo.divergedDetail == nil)
        #expect(!repo.isDiverged)
    }

    @Test func legacyReposDefaultBranchIsMain() throws {
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
        #expect(repo.defaultBranch == "main")
        #expect(repo.divergedDetail == nil)
    }

    @Test func normalizedBranchStripsRefsHeadsPrefix() {
        #expect(RepoConfig.normalizedBranch("refs/heads/develop") == "develop")
        #expect(RepoConfig.normalizedBranch("  ") == "main")
    }
}

struct VerificationFrequencyTests {
    @Test func weeklyIsDefaultInterval() {
        #expect(VerificationFrequency.week1.interval == 604_800)
        #expect(VerificationPreferences.default.frequency == .week1)
        #expect(VerificationPreferences.default.sampleSize == 3)
    }

    @Test func sampleSizeIsClamped() {
        #expect(VerificationPreferences.clampedSampleSize(0) == 1)
        #expect(VerificationPreferences.clampedSampleSize(999) == 50)
    }
}

// MARK: - Form Validation

@MainActor
struct AddEditRepoValidationTests {
    private func setPrimaryTargetURL(_ vm: AddEditRepoViewModel, _ url: String) {
        vm.targets[0].url = url
    }

    @Test func emptyNameIsInvalid() {
        let vm = AddEditRepoViewModel()
        vm.srcURL = "git@github.com:user/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        _ = vm.validate()
        #expect(vm.nameError != nil)
    }

    @Test func whitespaceOnlyNameIsInvalid() {
        let vm = AddEditRepoViewModel()
        vm.name = "   "
        vm.srcURL = "git@github.com:user/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        _ = vm.validate()
        #expect(vm.nameError != nil)
    }

    @Test func sshURLsAreValid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "git@gitlab.com:org/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/repo.git")
        #expect(vm.validate())
        #expect(vm.srcError == nil)
        #expect(vm.targetErrors.isEmpty)
    }

    @Test func httpsURLsAreValid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "https://github.com/user/repo.git"
        setPrimaryTargetURL(vm, "https://github.com/user/mirror.git")
        #expect(vm.validate())
    }

    @Test func invalidURLIsRejected() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "not-a-url"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        _ = vm.validate()
        #expect(vm.srcError != nil)
        #expect(vm.targetErrors.isEmpty)
    }

    @Test func emptyURLsAreInvalid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        _ = vm.validate()
        #expect(vm.srcError != nil)
        #expect(!vm.targetErrors.isEmpty)
    }

    @Test func allDisabledTargetsAreInvalid() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "git@github.com:user/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        vm.targets[0].enabled = false
        _ = vm.validate()
        #expect(!vm.targetErrors.isEmpty)
    }

    @Test func buildRepoConfigKeepsDestructivePushPolicy() {
        let vm = AddEditRepoViewModel()
        vm.name = "my-repo"
        vm.srcURL = "git@gitlab.com:org/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/repo.git")
        vm.destructivePushPolicy = .auto

        let repo = vm.buildRepoConfig()

        #expect(repo.destructivePushPolicy == .auto)
        #expect(repo.targets.count == 1)
    }

    @Test func buildRepoConfigPreservesHealthFieldsWhenEditing() {
        let lastSyncedAt = Date(timeIntervalSince1970: 1_777_080_000)
        let lastSuccessfulSyncedAt = lastSyncedAt.addingTimeInterval(-3_600)
        let lastVerifiedAt = lastSyncedAt.addingTimeInterval(120)
        let existingRepo = RepoConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            name: "old-name",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            defaultBranch: "develop",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: "network failed",
            consecutiveFailureCount: 4,
            lastVerifiedAt: lastVerifiedAt,
            divergedDetail: "内容分歧"
        )
        let vm = AddEditRepoViewModel(editing: existingRepo)
        vm.name = "new-name"

        let repo = vm.buildRepoConfig()

        #expect(repo.name == "new-name")
        #expect(repo.defaultBranch == "develop")
        #expect(repo.lastSyncedAt == lastSyncedAt)
        #expect(repo.lastSuccessfulSyncedAt == lastSuccessfulSyncedAt)
        #expect(repo.lastSyncError == "network failed")
        #expect(repo.consecutiveFailureCount == 4)
        #expect(repo.lastVerifiedAt == lastVerifiedAt)
        #expect(repo.divergedDetail == "内容分歧")
        #expect(repo.targets.count == 1)
    }

    @Test func buildRepoConfigSupportsMultipleTargets() {
        let vm = AddEditRepoViewModel()
        vm.name = "multi"
        vm.srcURL = "git@github.com:user/repo.git"
        vm.targets[0].url = "git@github.com:user/mirror-a.git"
        vm.addTarget()
        vm.targets[1].url = "git@gitlab.com:user/mirror-b.git"
        vm.targets[1].enabled = false

        let repo = vm.buildRepoConfig()

        #expect(repo.targets.count == 2)
        #expect(repo.enabledTargets.count == 1)
        #expect(repo.enabledTargets[0].url.contains("mirror-a"))
    }

    @Test func buildRepoConfigNormalizesTags() {
        let vm = AddEditRepoViewModel()
        vm.name = "tagged"
        vm.srcURL = "git@github.com:user/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        vm.tags = [" work ", "work", "oss", "  "]

        let repo = vm.buildRepoConfig()

        #expect(repo.tags == ["work", "oss"])
    }

    @Test func editingRepoPreservesTags() {
        let existingRepo = RepoConfig(
            name: "tagged",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            tags: ["work", "client"]
        )
        let vm = AddEditRepoViewModel(editing: existingRepo)

        #expect(vm.tags == ["work", "client"])
    }
}

// MARK: - ReposDocument migration

struct ReposDocumentMigrationTests {
    @Test func loadsLegacyBareArrayAsVersionOne() throws {
        let json = """
        [
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
        ]
        """

        let repos = try RepoStore.decodeRepos(from: Data(json.utf8))

        #expect(repos.count == 1)
        #expect(repos[0].targets.count == 1)
        #expect(repos[0].targets[0].url == "git@github.com:user/mirror.git")
    }

    @Test func loadsVersionTwoDocumentEnvelope() throws {
        let json = """
        {
          "version": 2,
          "repos": [
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "name": "v2-repo",
              "srcURL": "git@github.com:user/repo.git",
              "targets": [
                {
                  "id": "00000000-0000-0000-0000-000000000003",
                  "url": "git@gitlab.com:user/mirror.git",
                  "auth": { "sshAgent": {} },
                  "enabled": true
                }
              ],
              "srcAuth": { "sshAgent": {} },
              "frequency": "手动",
              "createdAt": "2026-04-25T12:00:00Z"
            }
          ]
        }
        """

        let repos = try RepoStore.decodeRepos(from: Data(json.utf8))

        #expect(repos.count == 1)
        #expect(repos[0].targets.count == 1)
        #expect(repos[0].targets[0].url == "git@gitlab.com:user/mirror.git")
    }

    @Test func saveWritesVersionTwoEnvelope() throws {
        let repo = RepoConfig(
            name: "saved",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let document = ReposDocument(repos: [repo])
        let data = try encoder.encode(document)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(object["version"] as? Int == 2)
        #expect((object["repos"] as? [Any])?.count == 1)
    }
}

// MARK: - Target sync aggregation

struct TargetSyncAggregationTests {
    @Test func aggregateSucceededRequiresAllTargets() {
        let results = [
            TargetSyncResult(targetID: UUID(), targetURL: "a.git", succeeded: true),
            TargetSyncResult(targetID: UUID(), targetURL: "b.git", succeeded: false, error: "fail")
        ]
        #expect(!SyncRecord.aggregateSucceeded(from: results))
    }

    @Test func partialFailureMessageIncludesCounts() {
        let results = [
            TargetSyncResult(targetID: UUID(), targetURL: "a.git", succeeded: true),
            TargetSyncResult(
                targetID: UUID(),
                targetURL: "b.git",
                succeeded: false,
                error: "Network error — check connectivity"
            )
        ]
        let message = SyncRecord.aggregateErrorMessage(from: results)
        #expect(message?.contains("1/2") == true)
        #expect(message?.contains("b.git") == true)
    }

    @Test func enabledTargetsFilterDisabledEntries() {
        let repo = RepoConfig(
            name: "multi",
            srcURL: "git@github.com:user/repo.git",
            targets: [
                MirrorTarget(url: "git@github.com:user/a.git", enabled: true),
                MirrorTarget(url: "git@gitlab.com:user/b.git", enabled: false)
            ]
        )
        #expect(repo.enabledTargets.count == 1)
        #expect(repo.enabledTargets[0].url.contains("a.git"))
    }
}


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

// MARK: - ProviderTokenScope

struct ProviderTokenScopeTests {
    @Test func parseGitHubOAuthScopesHeader() {
        let scopes = ProviderTokenScope.parseGitHubOAuthScopesHeader("repo, read:org, user")
        #expect(scopes == Set(["repo", "read:org", "user"]))
    }

    @Test func parseGitHubOAuthScopesHeaderIgnoresWhitespace() {
        let scopes = ProviderTokenScope.parseGitHubOAuthScopesHeader(" repo , read:org ")
        #expect(scopes == Set(["repo", "read:org"]))
    }

    @Test func parseGitHubOAuthScopesHeaderEmptyReturnsEmptySet() {
        #expect(ProviderTokenScope.parseGitHubOAuthScopesHeader(nil).isEmpty)
        #expect(ProviderTokenScope.parseGitHubOAuthScopesHeader("").isEmpty)
        #expect(ProviderTokenScope.parseGitHubOAuthScopesHeader("   ").isEmpty)
    }

    @Test func parseGitLabScopesNormalizesValues() {
        let scopes = ProviderTokenScope.parseGitLabScopes([" read_api ", "read_user", ""])
        #expect(scopes == Set(["read_api", "read_user"]))
    }

    @Test func githubRepoScopeAcceptsPublicRepoFallback() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["public_repo"],
            usage: .sourceListing(provider: .github, organizationScope: false)
        )
        #expect(validation.isFullyAuthorized)
        #expect(validation.missingRequiredScopes.isEmpty)
    }

    @Test func githubOrganizationRequiresReadOrg() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["repo"],
            usage: .sourceListing(provider: .github, organizationScope: true)
        )
        #expect(!validation.isFullyAuthorized)
        #expect(validation.missingRequiredScopes == ["read:org"])
        #expect(validation.bannerText.contains("read:org"))
    }

    @Test func gitlabApiScopeSatisfiesReadApiRequirement() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["api"],
            usage: .sourceListing(provider: .gitlab, organizationScope: false)
        )
        #expect(validation.isFullyAuthorized)
    }

    @Test func gitlabMissingReadApiShowsWarningCopy() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["read_user"],
            usage: .sourceListing(provider: .gitlab, organizationScope: false)
        )
        #expect(!validation.isFullyAuthorized)
        #expect(validation.missingRequiredScopes == ["read_api"])
        #expect(validation.bannerText.contains("缺少必需权限: read_api"))
    }

    @Test func giteaAllScopeSatisfiesWriteRepository() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["all"],
            usage: .giteaTargetCreate
        )
        #expect(validation.isFullyAuthorized)
    }

    @Test func giteaMissingWriteRepositoryShowsWarningCopy() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["read:repository"],
            usage: .giteaTargetCreate
        )
        #expect(!validation.isFullyAuthorized)
        #expect(validation.missingRequiredScopes == ["write:repository"])
        #expect(validation.bannerText.contains("write:repository"))
    }

    @Test func fullyAuthorizedBannerListsScopes() {
        let validation = ProviderTokenScope.validate(
            grantedScopes: ["repo", "read:org"],
            usage: .sourceListing(provider: .github, organizationScope: true)
        )
        #expect(validation.isFullyAuthorized)
        #expect(validation.bannerText == "Token 有效, scopes = [read:org, repo]")
    }
}

// MARK: - ProviderTokenScopeCache

struct ProviderTokenScopeCacheTests {
    @Test func cachesScopesForTwentyFourHours() {
        let key = "test-cache-\(UUID().uuidString)"
        let fetchedAt = Date(timeIntervalSince1970: 1_000_000)
        ProviderTokenScopeCache.save(key: key, scopes: ["repo", "read:org"], fetchedAt: fetchedAt)

        let loaded = ProviderTokenScopeCache.load(
            key: key,
            now: fetchedAt.addingTimeInterval(ProviderTokenScope.cacheLifetime - 1)
        )

        #expect(loaded == Set(["repo", "read:org"]))
        ProviderTokenScopeCache.remove(key: key)
    }

    @Test func expiresCacheAfterTwentyFourHours() {
        let key = "test-cache-\(UUID().uuidString)"
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000)
        ProviderTokenScopeCache.save(key: key, scopes: ["read_api"], fetchedAt: fetchedAt)

        let loaded = ProviderTokenScopeCache.load(
            key: key,
            now: fetchedAt.addingTimeInterval(ProviderTokenScope.cacheLifetime)
        )

        #expect(loaded == nil)
    }

    @Test func cacheKeyDiffersByProviderAndBaseURL() {
        let token = "secret-token"
        let githubKey = ProviderTokenScopeCache.cacheKey(provider: .github, token: token)
        let gitlabKey = ProviderTokenScopeCache.cacheKey(
            provider: .gitlab,
            token: token,
            baseURL: URL(string: "https://gitlab.example.com/api/v4")!
        )
        let gitlabDefaultKey = ProviderTokenScopeCache.cacheKey(provider: .gitlab, token: token)

        #expect(githubKey != gitlabKey)
        #expect(gitlabKey != gitlabDefaultKey)
    }
}

// MARK: - App Intents support

struct RepoIntentSupportTests {
    private func makeRepo(
        name: String,
        lastSyncedAt: Date? = nil,
        lastSuccessfulSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        divergedDetail: String? = nil,
        lastVerifiedAt: Date? = nil
    ) -> RepoConfig {
        RepoConfig(
            name: name,
            srcURL: "git@github.com:user/\(name).git",
            dstURL: "git@github.com:user/\(name)-mirror.git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: lastSyncError,
            divergedDetail: divergedDetail,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    @Test func repoLookupIsCaseInsensitive() {
        let repos = [makeRepo(name: "My Docs")]
        #expect(RepoIntentSupport.repo(matchingName: "my docs", in: repos)?.name == "My Docs")
        #expect(RepoIntentSupport.repo(matchingName: "  My Docs  ", in: repos)?.name == "My Docs")
        #expect(RepoIntentSupport.repo(matchingName: "missing", in: repos) == nil)
        #expect(RepoIntentSupport.repo(matchingName: "   ", in: repos) == nil)
    }

    @Test func snapshotPrefersInProgressSync() {
        let repo = makeRepo(name: "docs", lastSuccessfulSyncedAt: Date(timeIntervalSince1970: 1_000))
        let snapshot = RepoIntentSupport.makeSnapshot(
            repo: repo,
            runtimeStatus: .idle,
            isSyncInProgress: true
        )

        #expect(snapshot.status == .syncing)
        #expect(snapshot.repoName == "docs")
    }

    @Test func snapshotMapsRuntimeFailureAndPersistedSuccess() {
        let syncedAt = Date(timeIntervalSince1970: 2_000)
        let repo = makeRepo(
            name: "docs",
            lastSyncedAt: syncedAt,
            lastSuccessfulSyncedAt: syncedAt
        )

        let failed = RepoIntentSupport.makeSnapshot(
            repo: repo,
            runtimeStatus: .failed("network failed"),
            isSyncInProgress: false
        )
        #expect(failed.status == .failure)
        #expect(failed.message == "network failed")
        #expect(failed.lastSyncedAt == syncedAt)

        let success = RepoIntentSupport.makeSnapshot(
            repo: repo,
            runtimeStatus: .idle,
            isSyncInProgress: false
        )
        #expect(success.status == .success)
        #expect(success.lastSyncedAt == syncedAt)
    }

    @Test func snapshotFallsBackToPersistedFailureDivergenceAndUnknown() {
        let failedAt = Date(timeIntervalSince1970: 3_000)
        let failedRepo = makeRepo(
            name: "failed",
            lastSyncedAt: failedAt,
            lastSyncError: "auth denied"
        )
        let failedSnapshot = RepoIntentSupport.makeSnapshot(
            repo: failedRepo,
            runtimeStatus: nil,
            isSyncInProgress: false
        )
        #expect(failedSnapshot.status == .failure)
        #expect(failedSnapshot.message == "auth denied")

        let divergedRepo = makeRepo(name: "diverged", divergedDetail: "tree mismatch")
        let divergedSnapshot = RepoIntentSupport.makeSnapshot(
            repo: divergedRepo,
            runtimeStatus: nil,
            isSyncInProgress: false
        )
        #expect(divergedSnapshot.status == .diverged)
        #expect(divergedSnapshot.message == "tree mismatch")

        let unknownRepo = makeRepo(name: "fresh")
        let unknownSnapshot = RepoIntentSupport.makeSnapshot(
            repo: unknownRepo,
            runtimeStatus: nil,
            isSyncInProgress: false
        )
        #expect(unknownSnapshot.status == .unknown)
    }
}

@MainActor
struct AppIntentBridgeTests {
    private func makeViewModel() -> AppViewModel {
        let suite = "gitrelay.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return AppViewModel(verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults))
    }

    @Test func triggerSyncReportsMissingRepository() {
        let vm = makeViewModel()
        AppIntentBridge.register(vm)

        do {
            try AppIntentBridge.triggerSync(repoName: "Missing")
            Issue.record("Expected repoNotFound error")
        } catch AppIntentBridgeError.repoNotFound(let name) {
            #expect(name == "Missing")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func triggerSyncAllUsesRegisteredViewModel() throws {
        let vm = makeViewModel()
        AppIntentBridge.register(vm)
        try AppIntentBridge.triggerSyncAll()
        #expect(vm.inProgressSyncIDs.isEmpty)
    }

    @Test func syncStatusSnapshotReturnsMappedStatus() throws {
        let vm = makeViewModel()
        AppIntentBridge.register(vm)
        let syncedAt = Date(timeIntervalSince1970: 4_000)
        vm.addRepo(RepoConfig(
            name: "Docs",
            srcURL: "git@github.com:user/docs.git",
            dstURL: "git@github.com:user/docs-mirror.git",
            lastSyncedAt: syncedAt,
            lastSuccessfulSyncedAt: syncedAt
        ))

        let snapshot = try AppIntentBridge.syncStatusSnapshot(repoName: "Docs")
        #expect(snapshot.status == .success)
        #expect(snapshot.lastSyncedAt == syncedAt)
    }
}

// MARK: - GitRelayCLI

struct GitRelayCLIParserTests {
    @Test func parsesListCommand() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "list"])
        #expect(result == .success(.list))
    }

    @Test func parsesSyncCommand() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "sync", "My Repo"])
        #expect(result == .success(.sync(name: "My Repo")))
    }

    @Test func parsesStatusForAllRepos() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "status"])
        #expect(result == .success(.status(name: nil)))
    }

    @Test func parsesStatusForNamedRepo() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "status", "docs"])
        #expect(result == .success(.status(name: "docs")))
    }

    @Test func parsesLogsWithTailFlag() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "logs", "docs", "--tail", "20"])
        #expect(result == .success(.logs(name: "docs", tail: 20)))
    }

    @Test func parsesLogsWithTailEqualsSyntax() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "logs", "docs", "--tail=5"])
        #expect(result == .success(.logs(name: "docs", tail: 5)))
    }

    @Test func rejectsMissingSubcommand() {
        let result = GitRelayCLIParser.parse(["gitrelayctl"])
        guard case .failure(.missingSubcommand) = result else {
            Issue.record("Expected missingSubcommand")
            return
        }
    }

    @Test func rejectsUnknownSubcommand() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "dance"])
        guard case .failure(.unknownSubcommand("dance")) = result else {
            Issue.record("Expected unknownSubcommand")
            return
        }
    }

    @Test func rejectsMissingSyncName() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "sync"])
        guard case .failure(.missingRepoName("sync")) = result else {
            Issue.record("Expected missingRepoName")
            return
        }
    }

    @Test func rejectsInvalidTailValue() {
        let result = GitRelayCLIParser.parse(["gitrelayctl", "logs", "docs", "--tail", "-1"])
        guard case .failure(.invalidTailValue("-1")) = result else {
            Issue.record("Expected invalidTailValue")
            return
        }
    }
}

struct GitRelayCLIExitCodeTests {
    @Test func mapsRepoNotFoundToExitCodeThree() {
        let code = GitRelayCLIExecutor.exitCode(for: HeadlessSyncError.repoNotFound("missing"))
        #expect(code == .repoNotFound)
        #expect(code.rawValue == 3)
    }

    @Test func mapsUsageErrorsToExitCodeTwo() {
        let code = GitRelayCLIExecutor.exitCode(for: GitRelayCLIParseError.missingSubcommand)
        #expect(code == .usage)
        #expect(code.rawValue == 2)
    }

    @Test func mapsOperationalFailuresToExitCodeOne() {
        let code = GitRelayCLIExecutor.exitCode(for: HeadlessSyncError.loadFailed("broken json"))
        #expect(code == .failure)
        #expect(code.rawValue == 1)
    }
}

struct GitRelayCLIStatusJSONTests {
    @Test func encodesSingleRepoStatusAsJSON() throws {
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = RepoSyncStatusSnapshot(
            repoName: "Docs",
            status: .success,
            lastSyncedAt: syncedAt,
            message: nil
        )
        let json = try GitRelayCLIFormatter.jsonString(
            GitRelayCLIFormatter.statusEntry(from: snapshot)
        )
        #expect(json.contains("\"repoName\" : \"Docs\""))
        #expect(json.contains("\"status\" : \"success\""))
        #expect(json.contains("2023-11-14T22:13:20Z"))
    }

    @Test func encodesAllRepoStatusesDocument() throws {
        let document = GitRelayCLIStatusDocument(repos: [
            GitRelayCLIStatusEntry(
                repoName: "A",
                status: .failure,
                lastSyncedAt: nil,
                message: "auth denied"
            ),
            GitRelayCLIStatusEntry(
                repoName: "B",
                status: .unknown,
                lastSyncedAt: nil,
                message: nil
            ),
        ])
        let json = try GitRelayCLIFormatter.jsonString(document)
        #expect(json.contains("\"repoName\" : \"A\""))
        #expect(json.contains("\"status\" : \"failure\""))
        #expect(json.contains("\"message\" : \"auth denied\""))
        #expect(json.contains("\"repoName\" : \"B\""))
    }
}

struct SyncLogStoreTests {
    @Test func appendLoadAndTailLogLines() throws {
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-cli-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let originalBase = Constants.baseDirectory
        setBaseDirectoryForTesting(base)

        defer { setBaseDirectoryForTesting(originalBase) }

        var record = SyncRecord(repoID: repoID, succeeded: true)
        record.finishedAt = Date(timeIntervalSince1970: 100)
        record.logLines = (1...5).map { "line \($0)" }

        try SyncLogStore.append(record, for: repoID)

        let loaded = try SyncLogStore.loadRecords(for: repoID)
        #expect(loaded.count == 1)
        #expect(loaded[0].logLines.count == 5)

        let tailTwo = try SyncLogStore.formattedLogLines(for: repoID, tail: 2)
        #expect(tailTwo == ["line 4", "line 5"])
    }
}

private func setBaseDirectoryForTesting(_ url: URL) {
    Constants.setBaseDirectoryForTesting(url)
}
