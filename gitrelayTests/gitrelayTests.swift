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
