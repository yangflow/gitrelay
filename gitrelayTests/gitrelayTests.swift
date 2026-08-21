import Foundation
import Testing
import UserNotifications
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

        #expect(plan.confirmationPrompt == "This will delete 2 refs and force-update 1 refs. Continue?")
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

    @Test func depthAndRefSpecsDefaultOnDecode() throws {
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

        #expect(repo.depth == nil)
        #expect(repo.resolvedRefSpecs == RepoConfig.defaultRefSpecs)
        #expect(!repo.usesSelectiveRefSync)
    }

    @Test func encodesDepthAndCustomRefSpecs() throws {
        let repo = RepoConfig(
            name: "partial",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            depth: 50,
            refSpecs: [
                "+refs/heads/main:refs/heads/main",
                "+refs/tags/v*:refs/tags/v*"
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(repo)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(object["depth"] as? Int == 50)
        #expect(object["refSpecs"] as? [String] == [
            "+refs/heads/main:refs/heads/main",
            "+refs/tags/v*:refs/tags/v*"
        ])
    }

    @Test func webhookEnabledDefaultsFalseOnDecode() throws {
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
        #expect(repo.webhookEnabled == false)
    }

    @Test func encodesWebhookEnabledWhenTrue() throws {
        let repo = RepoConfig(
            name: "hooked",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            webhookEnabled: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(repo)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["webhookEnabled"] as? Bool == true)
    }
}

// MARK: - GitSyncArguments

struct GitSyncArgumentsTests {
    @Test func defaultRefSpecsMatchGitMirrorConvention() {
        #expect(RepoConfig.defaultRefSpecs == [
            "+refs/heads/*:refs/heads/*",
            "+refs/tags/*:refs/tags/*"
        ])
    }

    @Test func fetchArgsIncludeDepthWhenShallow() {
        let args = GitSyncArguments.fetchArgs(
            depth: 50,
            refSpecs: RepoConfig.defaultRefSpecs
        )

        #expect(args == [
            "fetch",
            "--prune",
            "--depth",
            "50",
            "origin",
            "+refs/heads/*:refs/heads/*",
            "+refs/tags/*:refs/tags/*"
        ])
    }

    @Test func fetchArgsOmitDepthForFullClone() {
        let args = GitSyncArguments.fetchArgs(
            depth: nil,
            refSpecs: RepoConfig.defaultRefSpecs
        )

        #expect(args == [
            "fetch",
            "--prune",
            "origin",
            "+refs/heads/*:refs/heads/*",
            "+refs/tags/*:refs/tags/*"
        ])
        #expect(!args.contains("--depth"))
    }

    @Test func pushRefSpecsDeriveFromFetchRefSpecs() {
        let pushSpecs = GitSyncArguments.pushRefSpecs(from: [
            "+refs/heads/main:refs/heads/main",
            "+refs/tags/v*:refs/tags/v*"
        ])

        #expect(pushSpecs == [
            "refs/heads/main:refs/heads/main",
            "refs/tags/v*:refs/tags/v*"
        ])
    }

    @Test func shallowCloneUsesSelectiveRefSync() {
        let repo = RepoConfig(
            name: "shallow",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            depth: 100
        )

        #expect(repo.isShallowClone)
        #expect(repo.usesSelectiveRefSync)
        #expect(repo.partialSyncWarning?.contains("shallow clone") == true)
    }

    @Test func customRefSpecsUseSelectiveRefSyncWithoutDepth() {
        let repo = RepoConfig(
            name: "filtered",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            refSpecs: ["+refs/heads/main:refs/heads/main"]
        )

        #expect(!repo.isShallowClone)
        #expect(repo.usesSelectiveRefSync)
        #expect(repo.partialSyncWarning?.contains("Custom ref filters") == true)
    }

    @Test func fullMirrorConfigDoesNotUseSelectiveRefSync() {
        let repo = RepoConfig(
            name: "full",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )

        #expect(!repo.usesSelectiveRefSync)
        #expect(repo.partialSyncWarning == nil)
    }

    @Test func selectivePushArgsDoNotUseMirrorFlag() {
        let args = GitSyncArguments.pushSelectiveArgs(
            dstURL: "git@github.com:user/mirror.git",
            refSpecs: ["refs/heads/main:refs/heads/main"],
            dryRun: true
        )

        #expect(args == [
            "push",
            "--dry-run",
            "git@github.com:user/mirror.git",
            "refs/heads/main:refs/heads/main"
        ])
        #expect(!args.contains("--mirror"))
    }

    @Test func cloneAndPushArgsRequestProgress() {
        let clone = GitSyncArguments.cloneMirrorArgs(
            srcURL: "git@github.com:user/repo.git",
            mirrorPath: "/tmp/mirror"
        )
        #expect(clone.contains("--progress"))

        let push = GitSyncArguments.pushMirrorArgs(dstURL: "git@github.com:user/mirror.git")
        #expect(push.contains("--progress"))

        let selective = GitSyncArguments.pushSelectiveArgs(
            dstURL: "git@github.com:user/mirror.git",
            refSpecs: ["refs/heads/main:refs/heads/main"]
        )
        #expect(selective.contains("--progress"))

        let fetch = GitSyncArguments.fetchArgs(
            depth: nil,
            refSpecs: RepoConfig.defaultRefSpecs,
            progress: true
        )
        #expect(fetch.contains("--progress"))
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
        #expect(sections[1].title == "Untagged")
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
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-vm-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        return AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults)
        )
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

// MARK: - WidgetHealthSnapshot

struct WidgetHealthSnapshotTests {
    @Test func builderShapesTodayCountsFromSyncHealthSummary() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        let yesterday = makeDate(year: 2026, month: 4, day: 24, hour: 12, calendar: calendar)

        let successRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            lastSyncedAt: now,
            lastSuccessfulSyncedAt: now
        )
        let failedRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            lastSyncedAt: now,
            lastSyncError: "network failed"
        )
        let notRunRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            lastSyncedAt: yesterday,
            lastSuccessfulSyncedAt: yesterday
        )

        let snapshot = WidgetHealthSnapshotBuilder.make(
            repos: [successRepo, failedRepo, notRunRepo],
            statuses: [:],
            inProgressSyncIDs: [],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.summary.succeededToday == 1)
        #expect(snapshot.summary.failedToday == 1)
        #expect(snapshot.summary.notRunToday == 1)
        #expect(snapshot.updatedAt == now)
    }

    @Test func attentionReposPrioritizeRecentFailuresThenStaleRepos() {
        let calendar = makeUTCCalendar()
        let now = makeDate(year: 2026, month: 4, day: 25, hour: 12, calendar: calendar)
        let recentFailure = now.addingTimeInterval(-300)
        let olderFailure = now.addingTimeInterval(-3_600)
        let staleSuccess = now.addingTimeInterval(-90_000)

        let recentFailureRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            name: "recent-failure",
            lastSyncedAt: recentFailure,
            lastSyncError: "timeout"
        )
        let olderFailureRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            name: "older-failure",
            lastSyncedAt: olderFailure,
            lastSyncError: "auth failed"
        )
        let staleRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            name: "stale-success",
            lastSyncedAt: staleSuccess,
            lastSuccessfulSyncedAt: staleSuccess
        )
        let healthyRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
            name: "healthy",
            lastSyncedAt: now,
            lastSuccessfulSyncedAt: now
        )

        let attention = WidgetHealthSnapshotBuilder.attentionRepos(
            repos: [healthyRepo, staleRepo, olderFailureRepo, recentFailureRepo],
            statuses: [:],
            inProgressSyncIDs: [],
            now: now,
            limit: 3
        )

        #expect(attention.map(\.name) == ["recent-failure", "older-failure", "stale-success"])
        #expect(attention[0].status == .failure)
        #expect(attention[2].status == .success)
    }

    @Test func snapshotStoreRoundTripsJSONWithoutCredentials() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer {
            WidgetHealthSnapshotStore.setContainerURLForTesting(nil)
            try? FileManager.default.removeItem(at: tempDir)
        }
        WidgetHealthSnapshotStore.setContainerURLForTesting(tempDir)

        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let snapshot = WidgetHealthSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            summary: WidgetHealthSummaryPayload(succeededToday: 2, failedToday: 1, notRunToday: 0),
            attentionRepos: [
                WidgetAttentionRepo(
                    id: repoID,
                    name: "core-api",
                    status: .failure,
                    lastSyncedAt: Date(timeIntervalSince1970: 1_777_000_000),
                    message: "network failed"
                )
            ]
        )

        try WidgetHealthSnapshotStore.write(snapshot)
        let loaded = WidgetHealthSnapshotStore.read()
        #expect(loaded == snapshot)

        let rawJSON = try String(contentsOf: WidgetHealthSnapshotStore.snapshotURL!, encoding: .utf8)
        #expect(!rawJSON.localizedCaseInsensitiveContains("token"))
        #expect(!rawJSON.localizedCaseInsensitiveContains("secret"))
        #expect(!rawJSON.localizedCaseInsensitiveContains("password"))
    }

    @Test func deepLinkParsesRepoUUID() {
        let repoID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let url = WidgetDeepLink.repoURL(id: repoID)

        #expect(WidgetDeepLink.repoID(from: url) == repoID)
        #expect(WidgetDeepLink.repoID(from: WidgetDeepLink.openAppURL()) == nil)
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
        name: String = "repo",
        lastSyncedAt: Date?,
        lastSuccessfulSyncedAt: Date? = nil,
        lastSyncError: String? = nil
    ) -> RepoConfig {
        RepoConfig(
            id: id,
            name: name,
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: lastSyncError
        )
    }
}

// MARK: - BackupCompleteness

struct BackupCompletenessTests {
    @Test func shallowRepoShowsIncompleteMark() {
        let repo = RepoConfig(
            name: "shallow",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            depth: 50
        )

        let completeness = BackupCompleteness.evaluate(repo: repo)

        #expect(completeness.showsIncompleteMark)
        #expect(completeness.reasons == [.shallowClone])
        #expect(completeness.helpText?.contains("shallow clone") == true)
    }

    @Test func fullRepoDoesNotShowIncompleteMark() {
        let repo = RepoConfig(
            name: "full",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )

        let completeness = BackupCompleteness.evaluate(repo: repo)

        #expect(!completeness.showsIncompleteMark)
        #expect(completeness.reasons.isEmpty)
        #expect(completeness.helpText == nil)
    }

    @Test func customRefFiltersShowIncompleteMark() {
        let repo = RepoConfig(
            name: "filtered",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            refSpecs: ["+refs/heads/main:refs/heads/main"]
        )

        let completeness = BackupCompleteness.evaluate(repo: repo)

        #expect(completeness.showsIncompleteMark)
        #expect(completeness.reasons == [.customRefFilters])
        #expect(completeness.helpText?.contains("custom ref filters") == true)
    }

    @Test func needsCredentialsAloneDoesNotShowIncompleteMark() {
        let repo = RepoConfig(
            name: "imported",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            needsCredentials: true
        )

        let completeness = BackupCompleteness.evaluate(repo: repo)

        #expect(!completeness.showsIncompleteMark)
        #expect(completeness.reasons.isEmpty)
    }

    @Test func missingGitLFSFromRecentSyncShowsIncompleteMark() {
        let repo = RepoConfig(
            name: "lfs",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )
        var record = SyncRecord(repoID: repo.id)
        record.succeeded = true
        record.finishedAt = Date()
        record.logLines = [LFSMirrorMessages.missingGitLFSWarning]

        let completeness = BackupCompleteness.evaluate(repo: repo, recentRecords: [record])

        #expect(completeness.showsIncompleteMark)
        #expect(completeness.reasons == [.missingGitLFSTool])
        #expect(completeness.helpText?.contains("git-lfs") == true)
    }

    @Test func shallowPlusMissingLFSListsBothReasons() {
        let repo = RepoConfig(
            name: "both",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            depth: 10
        )
        var record = SyncRecord(repoID: repo.id)
        record.succeeded = true
        record.logLines = [LFSMirrorMessages.missingGitLFSWarning]

        let completeness = BackupCompleteness.evaluate(repo: repo, recentRecords: [record])

        #expect(completeness.showsIncompleteMark)
        #expect(completeness.reasons == [.shallowClone, .missingGitLFSTool])
        #expect(completeness.helpText?.contains("shallow clone") == true)
        #expect(completeness.helpText?.contains("git-lfs") == true)
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

    @Test func queuedAndSyncingCaptionsPreferRuntimePhase() {
        let now = Date(timeIntervalSince1970: 1_777_080_000)
        let repo = makeRepo(lastSyncedAt: now, lastSuccessfulSyncedAt: now)

        let queued = RepoRowHealthPresentation.caption(
            for: repo,
            status: .queued,
            now: now
        )
        #expect(queued.kind == .queued)
        #expect(!queued.isStale)

        let phase = SyncPhase(.cloningSource, progressDetail: "12 / 100 objects")
        let syncing = RepoRowHealthPresentation.caption(
            for: repo,
            status: .syncing,
            syncPhase: phase,
            now: now
        )
        #expect(syncing.kind == .syncing(phase.displayCaption))
        #expect(phase.displayCaption.contains("12 / 100"))
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
        lastSyncedAt: Date? = nil,
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

// MARK: - RepoFailureNextStep

@MainActor
struct RepoFailureNextStepTests {
    @Test func authFailureOffersReenterCredentialsAndOpenLog() {
        guard let message = SyncFailureClassifier.displayMessage(for: .authentication) else {
            Issue.record("expected authentication display message")
            return
        }
        let repo = makeRepo(lastSyncError: message)
        let step = RepoFailureNextStep.make(
            repo: repo,
            status: .failed(message)
        )

        #expect(step.primaryAction == .reenterCredentials)
        #expect(step.showsOpenLog)
        #expect(step.missingRepositorySide == nil)
        #expect(step.missingGitLFSInstallHint == nil)
    }

    @Test func needsCredentialsOffersReenterCredentials() {
        var repo = makeRepo()
        repo.needsCredentials = true
        let step = RepoFailureNextStep.make(
            repo: repo,
            status: .failed(RepoCredentialGate.missingCredentialsMessage)
        )

        #expect(step.primaryAction == .reenterCredentials)
        #expect(step.showsOpenLog)
    }

    @Test func missingGitLFSShowsInstallHintWithoutAuthAction() {
        let repo = makeRepo()
        var record = SyncRecord(repoID: repo.id)
        record.succeeded = true
        record.finishedAt = Date()
        record.logLines = [
            LFSMirrorMessages.missingGitLFSWarning,
            LFSMirrorMessages.installHint,
        ]

        let step = RepoFailureNextStep.make(
            repo: repo,
            status: .idle,
            recentRecords: [record]
        )

        #expect(step.primaryAction == nil)
        #expect(step.showsReenterCredentials == false)
        #expect(step.missingGitLFSInstallHint == LFSMirrorMessages.installHint)
        #expect(step.showsOpenLog)
    }

    @Test func repositoryNotFoundOnSourceIsLabeledSource() {
        guard let message = SyncFailureClassifier.displayMessage(for: .repositoryNotFound) else {
            Issue.record("expected repository-not-found display message")
            return
        }
        let repo = makeRepo(lastSyncError: message)
        var record = SyncRecord(repoID: repo.id)
        record.succeeded = false
        record.finishedAt = Date()
        record.targetResults = []

        let step = RepoFailureNextStep.make(
            repo: repo,
            status: .failed(message),
            recentRecords: [record]
        )

        #expect(step.primaryAction == nil)
        #expect(step.missingRepositorySide == .source)
        #expect(step.missingRepositoryCaption != nil)
        #expect(step.showsOpenLog)
    }

    @Test func repositoryNotFoundOnDestinationIsLabeledDestination() {
        guard let message = SyncFailureClassifier.displayMessage(for: .repositoryNotFound) else {
            Issue.record("expected repository-not-found display message")
            return
        }
        let repo = makeRepo(lastSyncError: message)
        let targetID = UUID()
        var record = SyncRecord(repoID: repo.id)
        record.succeeded = false
        record.finishedAt = Date()
        record.targetResults = [
            TargetSyncResult(
                targetID: targetID,
                targetURL: "git@github.com:user/mirror.git",
                succeeded: false,
                error: message
            ),
        ]
        guard let aggregate = SyncRecord.aggregateErrorMessage(from: record.targetResults) else {
            Issue.record("expected aggregate destination error message")
            return
        }

        let step = RepoFailureNextStep.make(
            repo: repo,
            status: .failed(aggregate),
            recentRecords: [record]
        )

        #expect(step.missingRepositorySide == .destination)
        #expect(step.primaryAction == nil)
        #expect(step.showsOpenLog)
    }

    @Test func requestingReenterCredentialsDoesNotMutateRepoConfig() {
        let suite = "gitrelay.tests.next-step.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-next-step-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            biometricAuthenticator: PermissiveBiometricAuthenticator()
        )
        let repo = makeRepo(
            lastSyncError: SyncFailureClassifier.displayMessage(for: .authentication)
        )
        vm.addRepo(repo)
        let before = vm.repos[0]

        vm.requestReenterCredentials(repoID: before.id)
        let afterReenter = vm.repos[0]
        vm.requestOpenSyncLog(repoID: before.id)
        let afterOpenLog = vm.repos[0]

        #expect(afterReenter == before)
        #expect(afterOpenLog == before)
        #expect(vm.pendingEditFocusAuthRepoID == before.id)
        #expect(vm.pendingScrollToSyncLogRepoID == before.id)
        #expect(vm.pendingMainWindowRepoID == before.id)
    }

    @Test func editViewModelPreservesConfigWhenOpeningForReenterCredentials() {
        let lastSyncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = RepoConfig(
            name: "keep-me",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            frequency: .hour1,
            defaultBranch: "develop",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSyncedAt,
            lastSyncError: SyncFailureClassifier.displayMessage(for: .authentication),
            consecutiveFailureCount: 2,
            tags: ["prod"],
            lfsMirrorMode: .auto,
            needsCredentials: false
        )

        let vm = AddEditRepoViewModel(editing: existing)
        let rebuilt = vm.buildRepoConfig()

        #expect(rebuilt.id == existing.id)
        #expect(rebuilt.name == "keep-me")
        #expect(rebuilt.srcURL == existing.srcURL)
        #expect(rebuilt.targets.map(\.url) == existing.targets.map(\.url))
        #expect(rebuilt.frequency == .hour1)
        #expect(rebuilt.defaultBranch == "develop")
        #expect(rebuilt.lastSyncedAt == lastSyncedAt)
        #expect(rebuilt.lastSyncError == existing.lastSyncError)
        #expect(rebuilt.consecutiveFailureCount == 2)
        #expect(rebuilt.tags == ["prod"])
    }

    private func makeRepo(lastSyncError: String? = nil) -> RepoConfig {
        RepoConfig(
            name: "repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lastSyncError: lastSyncError
        )
    }
}

struct SyncFailureClassifierTests {
    @Test func classifiesAuthAndNotFoundWithStableDisplayMessages() {
        let auth = SyncFailureClassifier.classifyError(
            GitError.processError(128, "Authentication failed for 'https://github.com/x/y.git/'")
        )
        #expect(auth == SyncFailureClassifier.displayMessage(for: .authentication))
        #expect(SyncFailureClassifier.kind(fromStoredMessage: auth) == .authentication)

        let missing = SyncFailureClassifier.classifyError(
            GitError.processError(128, "fatal: repository 'https://github.com/x/missing.git' not found")
        )
        #expect(missing == SyncFailureClassifier.displayMessage(for: .repositoryNotFound))
        #expect(SyncFailureClassifier.kind(fromStoredMessage: missing) == .repositoryNotFound)
    }

    @Test func redactsCredentialsInUnclassifiedMessages() {
        let message = SyncFailureClassifier.classifyError(
            GitError.processError(
                128,
                "fatal: unable to access 'https://secret-token@example.com/x/y.git/': weird local error"
            )
        )
        #expect(!message.contains("secret-token"))
        #expect(message.contains("https://****@"))
    }
}

// MARK: - MenuBarPopoverFilter

struct MenuBarPopoverFilterTests {
    private func makeRepo(name: String, tags: [String] = []) -> RepoConfig {
        RepoConfig(
            name: name,
            srcURL: "git@github.com:user/\(name).git",
            dstURL: "git@github.com:user/\(name)-mirror.git",
            tags: tags
        )
    }

    @Test func emptySearchReturnsAllRepos() {
        let repos = [
            makeRepo(name: "alpha"),
            makeRepo(name: "beta")
        ]

        #expect(MenuBarPopoverFilter.filteredRepos(repos, searchText: "") == repos)
        #expect(MenuBarPopoverFilter.filteredRepos(repos, searchText: "   ") == repos)
    }

    @Test func searchMatchesRepoNameCaseInsensitively() {
        let alpha = makeRepo(name: "AlphaProject")
        let beta = makeRepo(name: "beta-service")
        let repos = [alpha, beta]

        #expect(MenuBarPopoverFilter.filteredRepos(repos, searchText: "alpha") == [alpha])
        #expect(MenuBarPopoverFilter.filteredRepos(repos, searchText: "SERVICE") == [beta])
    }

    @Test func searchMatchesTags() {
        let tagged = makeRepo(name: "mirror-a", tags: ["production"])
        let other = makeRepo(name: "mirror-b", tags: ["staging"])
        let repos = [tagged, other]

        #expect(MenuBarPopoverFilter.filteredRepos(repos, searchText: "prod") == [tagged])
    }

    @Test func canTriggerSyncAllowsAllStatusesExceptSyncingAndQueued() {
        #expect(MenuBarPopoverFilter.canTriggerSync(for: .idle))
        #expect(MenuBarPopoverFilter.canTriggerSync(for: .unknown))
        #expect(MenuBarPopoverFilter.canTriggerSync(for: .failed("network")))
        #expect(MenuBarPopoverFilter.canTriggerSync(for: .diverged("detail")))
        #expect(!MenuBarPopoverFilter.canTriggerSync(for: .syncing))
        #expect(!MenuBarPopoverFilter.canTriggerSync(for: .queued))
    }
}

// MARK: - SidebarRepoFilter

struct SidebarRepoFilterTests {
    private func makeRepo(
        name: String,
        srcURL: String? = nil,
        dstURL: String? = nil,
        targets: [MirrorTarget]? = nil,
        tags: [String] = [],
        lastSyncedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        divergedDetail: String? = nil
    ) -> RepoConfig {
        if let targets {
            return RepoConfig(
                name: name,
                srcURL: srcURL ?? "git@github.com:user/\(name).git",
                targets: targets,
                lastSyncedAt: lastSyncedAt,
                lastSuccessfulSyncedAt: lastSyncedAt,
                divergedDetail: divergedDetail,
                tags: tags
            )
        }
        return RepoConfig(
            name: name,
            srcURL: srcURL ?? "git@github.com:user/\(name).git",
            dstURL: dstURL ?? "git@github.com:user/\(name)-mirror.git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSyncedAt,
            divergedDetail: divergedDetail,
            tags: tags
        )
    }

    @Test func searchMatchesRepoNameCaseInsensitively() {
        let alpha = makeRepo(name: "AlphaProject")
        let beta = makeRepo(name: "beta-service")
        let repos = [alpha, beta]

        let hit = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "alpha",
            statusFilter: .all,
            statuses: [:]
        )
        #expect(hit == [alpha])

        let upper = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "SERVICE",
            statusFilter: .all,
            statuses: [:]
        )
        #expect(upper == [beta])
    }

    @Test func searchMatchesTags() {
        let tagged = makeRepo(name: "mirror-a", tags: ["production"])
        let other = makeRepo(name: "mirror-b", tags: ["staging"])
        let repos = [tagged, other]

        let hit = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "prod",
            statusFilter: .all,
            statuses: [:]
        )
        #expect(hit == [tagged])
    }

    @Test func searchMatchesSourceAndDestinationURLsIncludingMultiTarget() {
        let multi = makeRepo(
            name: "multi",
            srcURL: "git@github.com:acme/source.git",
            targets: [
                MirrorTarget(url: "git@gitlab.com:acme/primary.git"),
                MirrorTarget(url: "git@backup.local:mirrors/secondary.git")
            ]
        )
        let other = makeRepo(name: "other")
        let repos = [multi, other]

        #expect(
            SidebarRepoFilter.filteredRepos(
                repos,
                searchText: "acme/source",
                statusFilter: .all,
                statuses: [:]
            ) == [multi]
        )
        #expect(
            SidebarRepoFilter.filteredRepos(
                repos,
                searchText: "backup.local",
                statusFilter: .all,
                statuses: [:]
            ) == [multi]
        )
    }

    @Test func failedFilterShowsOnlyFailedStatuses() {
        let ok = makeRepo(name: "ok")
        let failed = makeRepo(name: "failed")
        let diverged = makeRepo(name: "diverged")
        let repos = [ok, failed, diverged]
        let statuses: [UUID: SyncStatus] = [
            ok.id: .idle,
            failed.id: .failed("network"),
            diverged.id: .diverged("tree mismatch")
        ]

        let hit = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "",
            statusFilter: .failed,
            statuses: statuses
        )
        #expect(hit == [failed])
    }

    @Test func clearingSearchRestoresFullFilteredSet() {
        let alpha = makeRepo(name: "Alpha")
        let beta = makeRepo(name: "Beta")
        let repos = [alpha, beta]
        let statuses: [UUID: SyncStatus] = [
            alpha.id: .failed("boom"),
            beta.id: .failed("boom")
        ]

        let narrowed = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "alpha",
            statusFilter: .failed,
            statuses: statuses
        )
        #expect(narrowed == [alpha])

        let restored = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "   ",
            statusFilter: .failed,
            statuses: statuses
        )
        #expect(restored == [alpha, beta])
    }

    @Test func searchAndStatusFilterCombineWithAND() {
        let failedAlpha = makeRepo(name: "Alpha")
        let failedBeta = makeRepo(name: "Beta")
        let idleAlpha = makeRepo(name: "AlphaIdle")
        let repos = [failedAlpha, failedBeta, idleAlpha]
        let statuses: [UUID: SyncStatus] = [
            failedAlpha.id: .failed("err"),
            failedBeta.id: .failed("err"),
            idleAlpha.id: .idle
        ]

        let hit = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "alpha",
            statusFilter: .failed,
            statuses: statuses
        )
        #expect(hit == [failedAlpha])
    }

    @Test func divergedFilterMatchesStatusOrPersistedDivergence() {
        let byStatus = makeRepo(name: "status-diverged")
        let byDetail = makeRepo(name: "detail-diverged", divergedDetail: "src != dst")
        let ok = makeRepo(name: "ok")
        let repos = [byStatus, byDetail, ok]
        let statuses: [UUID: SyncStatus] = [
            byStatus.id: .diverged("live"),
            byDetail.id: .idle,
            ok.id: .idle
        ]

        let hit = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "",
            statusFilter: .diverged,
            statuses: statuses
        )
        #expect(hit == [byStatus, byDetail])
    }

    @Test func notSyncedFilterMatchesNeverSyncedCaptionPath() {
        let neverSynced = makeRepo(name: "fresh", lastSyncedAt: nil)
        let synced = makeRepo(name: "done")
        let repos = [neverSynced, synced]

        let hit = SidebarRepoFilter.filteredRepos(
            repos,
            searchText: "",
            statusFilter: .notSynced,
            statuses: [:]
        )
        #expect(hit == [neverSynced])
    }
}

// MARK: - DesignTokens

struct DesignTokensTests {
    @Test func sidebarWidthStaysNarrowIceLikeRange() {
        #expect(DesignTokens.Layout.sidebarMinWidth == 200)
        #expect(DesignTokens.Layout.sidebarIdealWidth == 240)
        #expect(DesignTokens.Layout.sidebarMaxWidth == 300)
        #expect(DesignTokens.Layout.sidebarMinWidth < DesignTokens.Layout.sidebarIdealWidth)
        #expect(DesignTokens.Layout.sidebarIdealWidth < DesignTokens.Layout.sidebarMaxWidth)
    }

    @Test func statusColorMappingCoversEverySyncStatus() {
        // Color equality needs SwiftUI in the test target; assert via a pure label instead.
        #expect(DesignTokens.StatusColor.label(for: .idle) == "idle")
        #expect(DesignTokens.StatusColor.label(for: .ahead(3)) == "ahead")
        #expect(DesignTokens.StatusColor.label(for: .syncing) == "syncing")
        #expect(DesignTokens.StatusColor.label(for: .queued) == "queued")
        #expect(DesignTokens.StatusColor.label(for: .diverged("diff")) == "diverged")
        #expect(DesignTokens.StatusColor.label(for: .failed("boom")) == "failed")
        #expect(DesignTokens.StatusColor.label(for: .unknown) == "unknown")
    }

    @Test func widgetStatusColorMappingCoversEveryKind() {
        #expect(DesignTokens.StatusColor.label(forWidgetStatus: .success) == "success")
        #expect(DesignTokens.StatusColor.label(forWidgetStatus: .failure) == "failure")
        #expect(DesignTokens.StatusColor.label(forWidgetStatus: .syncing) == "syncing")
        #expect(DesignTokens.StatusColor.label(forWidgetStatus: .queued) == "queued")
        #expect(DesignTokens.StatusColor.label(forWidgetStatus: .diverged) == "diverged")
        #expect(DesignTokens.StatusColor.label(forWidgetStatus: .unknown) == "unknown")
    }

    @Test func chromeMaterialsAreDistinctRoles() {
        #expect(DesignTokens.ChromeRole.sidebar.material == .sidebar)
        #expect(DesignTokens.ChromeRole.detail.material == .detail)
        #expect(DesignTokens.ChromeRole.popover.material == .popover)
        #expect(DesignTokens.ChromeRole.sheet.material == .sheet)
        #expect(DesignTokens.Material.sidebar != DesignTokens.Material.detail)
        #expect(DesignTokens.Material.footer != DesignTokens.Material.sidebar)
        #expect(DesignTokens.Material.popover != DesignTokens.Material.sheet)
        #expect(DesignTokens.Material.sidebar.tokenName == "sidebar")
        #expect(DesignTokens.Material.detail.tokenName == "detail")
        #expect(DesignTokens.Material.footer.tokenName == "footer")
        #expect(DesignTokens.Material.popover.tokenName == "popover")
        #expect(DesignTokens.Material.sheet.tokenName == "sheet")
    }

    @Test func sharedLayoutTokensStayStable() {
        #expect(DesignTokens.Layout.popoverWidth == 280)
        #expect(DesignTokens.Layout.settingsMinWidth == 560)
        #expect(DesignTokens.Layout.settingsSidebarMinWidth == 140)
        #expect(DesignTokens.Layout.settingsSidebarIdealWidth == 160)
        #expect(DesignTokens.Layout.settingsSidebarMaxWidth == 200)
        #expect(DesignTokens.Layout.settingsDetailMinWidth == 380)
        #expect(DesignTokens.Layout.settingsSidebarMinWidth < DesignTokens.Layout.settingsSidebarIdealWidth)
        #expect(DesignTokens.Layout.settingsSidebarIdealWidth < DesignTokens.Layout.settingsSidebarMaxWidth)
        #expect(DesignTokens.Spacing.sheetFooter == 16)
        #expect(DesignTokens.Size.statusDot == 8)
        #expect(DesignTokens.Size.menuBarIconPointSize == 16)
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
        #expect(message.contains("Target repository") || message.contains("target"))
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

    @Test func buildRepoConfigPersistsDepthAndRefSpecs() {
        let vm = AddEditRepoViewModel()
        vm.name = "partial"
        vm.srcURL = "git@github.com:user/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        vm.depthText = "50"
        vm.refSpecsText = """
        +refs/heads/main:refs/heads/main
        +refs/tags/v*:refs/tags/v*
        """

        let repo = vm.buildRepoConfig()

        #expect(repo.depth == 50)
        #expect(repo.resolvedRefSpecs == [
            "+refs/heads/main:refs/heads/main",
            "+refs/tags/v*:refs/tags/v*"
        ])
        #expect(repo.usesSelectiveRefSync)
    }

    @Test func invalidDepthIsRejected() {
        let vm = AddEditRepoViewModel()
        vm.name = "partial"
        vm.srcURL = "git@github.com:user/repo.git"
        setPrimaryTargetURL(vm, "git@github.com:user/mirror.git")
        vm.depthText = "0"

        #expect(!vm.validate())
        #expect(vm.depthError != nil)
    }

    @Test func editingRepoLoadsAdvancedOptions() {
        let existingRepo = RepoConfig(
            name: "partial",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            depth: 25,
            refSpecs: ["+refs/heads/main:refs/heads/main"]
        )
        let vm = AddEditRepoViewModel(editing: existingRepo)

        #expect(vm.depthText == "25")
        #expect(vm.refSpecsText == "+refs/heads/main:refs/heads/main")
        #expect(vm.partialSyncWarning != nil)
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

// MARK: - Add repo two-step + drop prefill (#59)

@MainActor
struct AddEditRepoTwoStepTests {
    private func setPrimaryTargetURL(_ vm: AddEditRepoViewModel, _ url: String) {
        vm.targets[0].url = url
    }

    @Test func newRepoStartsOnBasicsStepWithSSHAgentDefault() {
        let suite = "AddEditRepoTwoStep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let vm = AddEditRepoViewModel(defaults: defaults)
        #expect(!vm.showsMoreOptions)
        #expect(vm.srcAuthMode == .sshAgent)
        #expect(vm.targets[0].authMode == .sshAgent)
    }

    @Test func defaultAuthReusesLastUsedMode() {
        let suite = "AddEditRepoTwoStep.lastAuth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        LastUsedAuthMode.save(.httpsToken, to: defaults)
        let vm = AddEditRepoViewModel(defaults: defaults)
        #expect(vm.srcAuthMode == .httpsToken)
        #expect(vm.targets[0].authMode == .httpsToken)
    }

    @Test func requiredFieldsAloneValidateAndBuildConfigForSync() {
        let vm = AddEditRepoViewModel()
        #expect(!vm.showsMoreOptions)
        vm.name = "quick-add"
        vm.srcURL = "git@github.com:acme/source.git"
        setPrimaryTargetURL(vm, "git@github.com:acme/mirror.git")
        vm.frequency = .hour1

        #expect(vm.validate())
        #expect(!vm.showsMoreOptions)

        let repo = vm.buildRepoConfig()
        #expect(repo.name == "quick-add")
        #expect(repo.srcURL == "git@github.com:acme/source.git")
        #expect(repo.targets.count == 1)
        #expect(repo.targets[0].url == "git@github.com:acme/mirror.git")
        #expect(repo.frequency == .hour1)
        #expect(repo.lfsMirrorMode == .auto)
        #expect(!repo.webhookEnabled)
        #expect(repo.tags.isEmpty)
        #expect(repo.depth == nil)
    }

    @Test func openMoreOptionsStaysOnStepOneWhenInvalid() {
        let vm = AddEditRepoViewModel()
        #expect(!vm.openMoreOptions())
        #expect(!vm.showsMoreOptions)
        #expect(vm.nameError != nil)

        vm.name = "ready"
        vm.srcURL = "git@github.com:acme/source.git"
        setPrimaryTargetURL(vm, "git@github.com:acme/mirror.git")
        #expect(vm.openMoreOptions())
        #expect(vm.showsMoreOptions)
    }

    @Test func droppedURLPrefillsSourceAndInferredName() {
        let prefill = RepoSourceDropParser.parse("https://github.com/acme/widget.git")
        #expect(prefill?.srcURL == "https://github.com/acme/widget.git")
        #expect(prefill?.inferredName == "widget")

        let vm = AddEditRepoViewModel(prefill: prefill)
        #expect(vm.srcURL == "https://github.com/acme/widget.git")
        #expect(vm.name == "widget")
    }

    @Test func shorthandHostPathPrefillsHTTPSRemote() {
        let prefill = RepoSourceDropParser.parse("github.com/org/repo")
        #expect(prefill?.srcURL == "https://github.com/org/repo.git")
        #expect(prefill?.inferredName == "repo")

        let vm = AddEditRepoViewModel(prefill: prefill)
        #expect(vm.validateBasics() == false) // still needs a target
        vm.targets[0].url = "git@github.com:org/mirror.git"
        #expect(vm.validateBasics())
        #expect(vm.srcURL == "https://github.com/org/repo.git")
    }

    @Test func localGitDirectoryPrefillsSourcePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-drop-\(UUID().uuidString)", isDirectory: true)
        let repoDir = root.appendingPathComponent("my-local-repo", isDirectory: true)
        let gitDir = repoDir.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fromWorkingTree = RepoSourceDropParser.parse(fileURL: repoDir)
        #expect(fromWorkingTree?.srcURL == repoDir.path)
        #expect(fromWorkingTree?.inferredName == "my-local-repo")

        let fromGitDir = RepoSourceDropParser.parse(fileURL: gitDir)
        #expect(fromGitDir?.srcURL == gitDir.path)
        #expect(fromGitDir?.inferredName == "my-local-repo")

        let vm = AddEditRepoViewModel(prefill: fromWorkingTree)
        vm.targets[0].url = "git@github.com:acme/mirror.git"
        #expect(vm.validate())
        #expect(vm.srcURL == repoDir.path)
        #expect(vm.name == "my-local-repo")
    }

    @Test func editingStillLoadsLFSAndWebhookFields() {
        let existing = RepoConfig(
            name: "edit-me",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lfsMirrorMode: .off,
            webhookEnabled: true
        )
        let vm = AddEditRepoViewModel(editing: existing)
        #expect(vm.showsMoreOptions)
        #expect(vm.lfsMirrorMode == .off)
        #expect(vm.webhookEnabled)

        vm.lfsMirrorMode = .auto
        vm.webhookEnabled = false
        let saved = vm.buildRepoConfig()
        #expect(saved.lfsMirrorMode == .auto)
        #expect(!saved.webhookEnabled)
    }

    @Test func rememberLastUsedAuthModePersistsWithoutSecrets() {
        let suite = "AddEditRepoTwoStep.remember.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let vm = AddEditRepoViewModel(defaults: defaults)
        vm.srcAuthMode = .sshKey
        vm.rememberLastUsedAuthMode()
        #expect(LastUsedAuthMode.load(from: defaults) == .sshKey)
        #expect(defaults.string(forKey: "AddEditRepo.lastUsedAuthMode") == AuthMode.sshKey.rawValue)
    }
}

struct RepoSourceDropParserTests {
    @Test func parsesSSHAndHTTPSRemotes() {
        let ssh = RepoSourceDropParser.parse("git@gitlab.com:group/app.git")
        #expect(ssh?.srcURL == "git@gitlab.com:group/app.git")
        #expect(ssh?.inferredName == "app")

        let https = RepoSourceDropParser.parse("https://github.com/acme/app.git")
        #expect(https?.inferredName == "app")
    }

    @Test func rejectsNonGitNoise() {
        #expect(RepoSourceDropParser.parse("hello world") == nil)
        #expect(RepoSourceDropParser.parse("/tmp/not-a-repo-\(UUID().uuidString)") == nil)
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
            == "4 consecutive failures — Network error"
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
        #expect(body.contains("4 repositories failed to sync"))
        #expect(body.contains("alpha"))
        #expect(body.contains("beta"))
        #expect(body.contains("gamma"))
        #expect(body.contains("and others"))
    }

    @Test func aggregatedBodyForSingleItemUsesRepoDetail() {
        let body = FailureNotificationCopy.aggregatedBody(
            items: [(repoName: "alpha", message: "Network error", count: 2)]
        )
        #expect(body.contains("alpha"))
        #expect(body.contains("Network error"))
        #expect(body.contains("2 consecutive failures"))
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

    @Test func quietHoursTakePrecedenceOverPowerNetwork() {
        let calendar = QuietHoursTestSupport.makeUTCCalendar()
        let quiet = QuietHoursSettings(isEnabled: true, startMinutes: 23 * 60, endMinutes: 7 * 60)
        let policy = SyncPausePolicy(
            pauseOnLowPowerMode: true,
            pauseOnExpensiveNetwork: true,
            quietHours: quiet
        )
        let inside = QuietHoursTestSupport.date(hour: 1, minute: 0, calendar: calendar)
        #expect(
            policy.pauseReason(
                isLowPowerMode: true,
                isExpensiveNetwork: true,
                date: inside,
                calendar: calendar
            ) == .quietHours
        )
    }
}

// MARK: - Quiet Hours (#47)

enum QuietHoursTestSupport {
    static func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    static func date(hour: Int, minute: Int, day: Int = 15, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

struct QuietHoursSettingsTests {
    private var utcCalendar: Calendar { QuietHoursTestSupport.makeUTCCalendar() }

    @Test func disabledWindowNeverContains() {
        let settings = QuietHoursSettings(isEnabled: false, startMinutes: 23 * 60, endMinutes: 7 * 60)
        let calendar = utcCalendar
        let inside = QuietHoursTestSupport.date(hour: 1, minute: 0, calendar: calendar)
        #expect(!settings.contains(inside, calendar: calendar))
    }

    @Test func sameDayWindowContainsOnlyInside() {
        let settings = QuietHoursSettings(isEnabled: true, startMinutes: 12 * 60, endMinutes: 14 * 60)
        let calendar = utcCalendar
        #expect(settings.contains(QuietHoursTestSupport.date(hour: 12, minute: 0, calendar: calendar), calendar: calendar))
        #expect(settings.contains(QuietHoursTestSupport.date(hour: 13, minute: 30, calendar: calendar), calendar: calendar))
        #expect(!settings.contains(QuietHoursTestSupport.date(hour: 14, minute: 0, calendar: calendar), calendar: calendar))
        #expect(!settings.contains(QuietHoursTestSupport.date(hour: 11, minute: 59, calendar: calendar), calendar: calendar))
    }

    @Test func midnightWrapWindowWorks() {
        let settings = QuietHoursSettings(isEnabled: true, startMinutes: 23 * 60, endMinutes: 7 * 60)
        let calendar = utcCalendar
        #expect(settings.contains(QuietHoursTestSupport.date(hour: 23, minute: 0, calendar: calendar), calendar: calendar))
        #expect(settings.contains(QuietHoursTestSupport.date(hour: 23, minute: 30, calendar: calendar), calendar: calendar))
        #expect(settings.contains(QuietHoursTestSupport.date(hour: 0, minute: 0, calendar: calendar), calendar: calendar))
        #expect(settings.contains(QuietHoursTestSupport.date(hour: 6, minute: 59, calendar: calendar), calendar: calendar))
        #expect(!settings.contains(QuietHoursTestSupport.date(hour: 7, minute: 0, calendar: calendar), calendar: calendar))
        #expect(!settings.contains(QuietHoursTestSupport.date(hour: 12, minute: 0, calendar: calendar), calendar: calendar))
        #expect(!settings.contains(QuietHoursTestSupport.date(hour: 22, minute: 59, calendar: calendar), calendar: calendar))
    }

    @Test func zeroWidthWindowIsNeverActive() {
        let settings = QuietHoursSettings(isEnabled: true, startMinutes: 8 * 60, endMinutes: 8 * 60)
        let calendar = utcCalendar
        #expect(!settings.contains(QuietHoursTestSupport.date(hour: 8, minute: 0, calendar: calendar), calendar: calendar))
    }
}

struct ScheduledSyncGateQuietHoursTests {
    private var utcCalendar: Calendar { QuietHoursTestSupport.makeUTCCalendar() }

    @Test func scheduledTickSkippedInsideQuietHours() {
        let calendar = utcCalendar
        let policy = SyncPausePolicy(
            pauseOnLowPowerMode: false,
            pauseOnExpensiveNetwork: false,
            quietHours: QuietHoursSettings(isEnabled: true, startMinutes: 23 * 60, endMinutes: 7 * 60)
        )
        let inside = QuietHoursTestSupport.date(hour: 2, minute: 15, calendar: calendar)
        #expect(
            !ScheduledSyncGate.shouldRunScheduledSync(
                pausePolicy: policy,
                isLowPowerMode: false,
                isExpensiveNetwork: false,
                at: inside,
                calendar: calendar
            )
        )
    }

    @Test func scheduledTickRunsOutsideQuietHours() {
        let calendar = utcCalendar
        let policy = SyncPausePolicy(
            pauseOnLowPowerMode: false,
            pauseOnExpensiveNetwork: false,
            quietHours: QuietHoursSettings(isEnabled: true, startMinutes: 23 * 60, endMinutes: 7 * 60)
        )
        let outside = QuietHoursTestSupport.date(hour: 10, minute: 0, calendar: calendar)
        #expect(
            ScheduledSyncGate.shouldRunScheduledSync(
                pausePolicy: policy,
                isLowPowerMode: false,
                isExpensiveNetwork: false,
                at: outside,
                calendar: calendar
            )
        )
    }

    @Test func manualSyncPathIgnoresQuietHoursGate() {
        // Manual / App Intent / webhook call `triggerSync` directly and must not consult the gate.
        let calendar = utcCalendar
        let policy = SyncPausePolicy(
            pauseOnLowPowerMode: true,
            pauseOnExpensiveNetwork: true,
            quietHours: QuietHoursSettings(isEnabled: true, startMinutes: 23 * 60, endMinutes: 7 * 60)
        )
        let inside = QuietHoursTestSupport.date(hour: 3, minute: 0, calendar: calendar)
        #expect(
            !ScheduledSyncGate.shouldRunScheduledSync(
                pausePolicy: policy,
                isLowPowerMode: false,
                isExpensiveNetwork: false,
                at: inside,
                calendar: calendar
            )
        )
        // Direct sync APIs remain available regardless of the scheduled gate outcome.
        #expect(policy.pauseReason(
            isLowPowerMode: false,
            isExpensiveNetwork: false,
            date: inside,
            calendar: calendar
        )?.isQuietHours == true)
    }
}

@MainActor
struct QuietHoursMonitorFakeClockTests {
    @Test func monitorTracksFakeClockAcrossWindowBoundary() {
        let calendar = QuietHoursTestSupport.makeUTCCalendar()
        let monitor = QuietHoursMonitor()
        monitor.calendar = calendar
        var current = QuietHoursTestSupport.date(hour: 1, minute: 30, calendar: calendar)
        monitor.now = { current }

        monitor.start(
            settings: QuietHoursSettings(isEnabled: true, startMinutes: 23 * 60, endMinutes: 7 * 60)
        )
        #expect(monitor.isActive)

        current = QuietHoursTestSupport.date(hour: 8, minute: 0, calendar: calendar)
        monitor.refresh()
        #expect(!monitor.isActive)

        monitor.stop()
    }
}

struct QuietHoursCatchUpTrackerTests {
    @Test func catchUpIsAtMostOncePerRepo() {
        var tracker = QuietHoursCatchUpTracker()
        let repoA = UUID()
        let repoB = UUID()

        // Many skipped ticks during quiet hours must not stack.
        tracker.noteScheduledSkip(repoID: repoA)
        tracker.noteScheduledSkip(repoID: repoA)
        tracker.noteScheduledSkip(repoID: repoA)
        tracker.noteScheduledSkip(repoID: repoB)

        let first = tracker.takePendingCatchUp()
        #expect(first == Set([repoA, repoB]))

        let second = tracker.takePendingCatchUp()
        #expect(second.isEmpty)

        tracker.noteScheduledSkip(repoID: repoA)
        tracker.clear(repoID: repoA)
        #expect(tracker.takePendingCatchUp().isEmpty)
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
        prefs.transientGitMaxAttempts = 4
        prefs.interruptionLevel = .timeSensitive
        prefs.pauseOnLowPowerMode = false
        prefs.pauseOnExpensiveNetwork = false
        prefs.quietHours = QuietHoursSettings(isEnabled: true, startMinutes: 22 * 60, endMinutes: 6 * 60)
        prefs.maxConcurrentSyncs = 3
        store.preferences = prefs

        let reloaded = NotificationPreferencesStore(defaults: defaults)
        #expect(reloaded.preferences.notificationsEnabled == false)
        #expect(reloaded.preferences.notifyOnFirstFailure == false)
        #expect(reloaded.preferences.consecutiveFailureThreshold == 5)
        #expect(reloaded.preferences.transientGitMaxAttempts == 4)
        #expect(reloaded.preferences.interruptionLevel == .timeSensitive)
        #expect(reloaded.preferences.pauseOnLowPowerMode == false)
        #expect(reloaded.preferences.pauseOnExpensiveNetwork == false)
        #expect(reloaded.preferences.quietHours.isEnabled == true)
        #expect(reloaded.preferences.quietHours.startMinutes == 22 * 60)
        #expect(reloaded.preferences.quietHours.endMinutes == 6 * 60)
        #expect(reloaded.preferences.maxConcurrentSyncs == 3)
    }

    @Test func resetToDefaultsRestoresFactoryValues() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.notificationsEnabled = false
        prefs.consecutiveFailureThreshold = 9
        prefs.transientGitMaxAttempts = 5
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

    @Test func clampsTransientGitMaxAttemptsToThreeMinuteBudget() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.transientGitMaxAttempts = 999
        store.preferences = prefs
        #expect(store.preferences.transientGitMaxAttempts == GitRetryPolicy.clampedMaxAttempts(999))
        #expect(store.preferences.gitRetryPolicy.maxAttempts == store.preferences.transientGitMaxAttempts)
    }

    @Test func clampsMaxConcurrentSyncsToOneThroughFour() {
        let suite = "gitrelay.tests.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotificationPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.maxConcurrentSyncs = 0
        store.preferences = prefs
        #expect(store.preferences.maxConcurrentSyncs == 1)

        prefs = store.preferences
        prefs.maxConcurrentSyncs = 99
        store.preferences = prefs
        #expect(store.preferences.maxConcurrentSyncs == 4)
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

    @Test func deferredAlertPayloadCarriesRepoIDOnly() {
        var focused: Bool? = true
        let notifier = SyncFailureNotifier(focusStatusProvider: { focused })
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000034")!

        notifier.handleSyncFailure(
            repoID: repoID,
            repoName: "demo",
            message: "Network error — check connectivity",
            consecutiveFailureCount: 1,
            preferences: .default
        )

        let alert = notifier.pendingDuringFocus[repoID]
        #expect(alert?.repoID == repoID)
        let userInfo = SyncFailureNotificationPayload.userInfo(repoID: repoID)
        #expect(SyncFailureNotificationPayload.repoID(from: userInfo) == repoID)
        #expect(userInfo.keys.count == 1)
        #expect(userInfo[SyncFailureNotifier.repoIDKey] as? String == repoID.uuidString)
    }

    @Test func redactsCredentialsBeforeQueuingAlert() {
        var focused: Bool? = true
        let notifier = SyncFailureNotifier(focusStatusProvider: { focused })
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000035")!

        notifier.handleSyncFailure(
            repoID: repoID,
            repoName: "demo",
            message: "fatal: could not read https://ghp_secretTOKEN@github.com/org/repo.git",
            consecutiveFailureCount: 1,
            preferences: .default
        )

        let message = notifier.pendingDuringFocus[repoID]?.message ?? ""
        #expect(!message.contains("ghp_secretTOKEN"))
        #expect(message.contains("****@") || message.contains("github.com"))
    }
}

// MARK: - SyncFailureNotification actions

struct SyncFailureNotificationRoutingTests {
    @Test func payloadCarriesRepoID() {
        let repoID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let userInfo = SyncFailureNotificationPayload.userInfo(repoID: repoID)
        #expect(SyncFailureNotificationPayload.repoID(from: userInfo) == repoID)
        #expect(userInfo[SyncFailureNotifier.repoIDKey] as? String == repoID.uuidString)
    }

    @Test func payloadRejectsMissingOrInvalidRepoID() {
        #expect(SyncFailureNotificationPayload.repoID(from: [:]) == nil)
        #expect(SyncFailureNotificationPayload.repoID(from: [SyncFailureNotifier.repoIDKey: "not-a-uuid"]) == nil)
    }

    @Test func actionsMapToSyncAgainAndOpen() {
        #expect(
            SyncFailureNotificationRouting.action(for: SyncFailureNotifier.syncAgainActionIdentifier)
                == .syncAgain
        )
        #expect(
            SyncFailureNotificationRouting.action(for: SyncFailureNotifier.retryActionIdentifier)
                == .syncAgain
        )
        #expect(
            SyncFailureNotificationRouting.action(for: SyncFailureNotifier.openActionIdentifier)
                == .open
        )
        #expect(
            SyncFailureNotificationRouting.action(for: UNNotificationDefaultActionIdentifier)
                == .open
        )
        #expect(SyncFailureNotificationRouting.action(for: UNNotificationDismissActionIdentifier) == nil)
        #expect(SyncFailureNotificationRouting.action(for: "unknown") == nil)
    }
}

@MainActor
struct SyncFailureNotificationActionMappingTests {
    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-failure-notif-actions-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            notificationPreferencesStore: NotificationPreferencesStore(defaults: defaults),
            biometricAuthenticator: PermissiveBiometricAuthenticator()
        )
        vm.suspendSyncEngineForTesting = true
        return vm
    }

    private func addSSHRepo(to vm: AppViewModel, name: String) -> UUID {
        let id = UUID()
        vm.addRepo(
            RepoConfig(
                id: id,
                name: name,
                srcURL: "git@github.com:user/\(name).git",
                dstURL: "git@github.com:user/\(name)-mirror.git",
                frequency: .manual
            )
        )
        return id
    }

    @Test func syncAgainActionMapsToTriggerSync() {
        let suite = "gitrelay.tests.failure-notif-sync-again.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)
        let repoID = addSSHRepo(to: vm, name: "retry-me")

        let userInfo = SyncFailureNotificationPayload.userInfo(repoID: repoID)
        vm.failureNotifier.handleAction(
            identifier: SyncFailureNotifier.syncAgainActionIdentifier,
            userInfo: userInfo
        )

        #expect(vm.inProgressSyncIDs.contains(repoID))
        #expect(vm.statuses[repoID] == .syncing)
    }

    @Test func openActionMapsToSelectRepoPath() {
        let suite = "gitrelay.tests.failure-notif-open.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)
        let repoID = addSSHRepo(to: vm, name: "open-me")

        let userInfo = SyncFailureNotificationPayload.userInfo(repoID: repoID)
        vm.failureNotifier.handleAction(
            identifier: SyncFailureNotifier.openActionIdentifier,
            userInfo: userInfo
        )

        #expect(vm.pendingMainWindowRepoID == repoID)
        #expect(vm.pendingScrollToSyncLogRepoID == repoID)
    }

    @Test func defaultTapMapsToSelectRepoPath() {
        let suite = "gitrelay.tests.failure-notif-default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)
        let repoID = addSSHRepo(to: vm, name: "tap-me")

        vm.failureNotifier.handleAction(
            identifier: UNNotificationDefaultActionIdentifier,
            userInfo: SyncFailureNotificationPayload.userInfo(repoID: repoID)
        )

        #expect(vm.pendingMainWindowRepoID == repoID)
    }

    @Test func notifierCallbacksFireForMappedActions() {
        let notifier = SyncFailureNotifier(focusStatusProvider: { false })
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-000000000036")!
        var synced: UUID?
        var opened: UUID?
        notifier.onSyncAgain = { synced = $0 }
        notifier.onOpen = { opened = $0 }

        let userInfo = SyncFailureNotificationPayload.userInfo(repoID: repoID)
        notifier.handleAction(
            identifier: SyncFailureNotifier.syncAgainActionIdentifier,
            userInfo: userInfo
        )
        notifier.handleAction(
            identifier: SyncFailureNotifier.openActionIdentifier,
            userInfo: userInfo
        )

        #expect(synced == repoID)
        #expect(opened == repoID)
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
        #expect(validation.bannerText.contains("required scopes are missing: read_api") || validation.bannerText.contains("read_api"))
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
        #expect(validation.bannerText == "Token is valid, scopes = [read:org, repo]")
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
            lastVerifiedAt: lastVerifiedAt,
            divergedDetail: divergedDetail
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

    @Test func snapshotMapsQueuedDistinctFromSyncing() {
        let repo = makeRepo(name: "waiting")
        let snapshot = RepoIntentSupport.makeSnapshot(
            repo: repo,
            runtimeStatus: .queued,
            isSyncInProgress: false
        )
        #expect(snapshot.status == .queued)
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
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-intent-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        return AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults)
        )
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
        #expect(json.contains("2023-11-14T22:13:20"))
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

// MARK: - SSHKeyGenerator

struct SSHKeyGeneratorTests {
    private func makeHomeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-ssh-tests-\(UUID().uuidString)")
    }

    @Test func defaultDisplayPathUsesGitRelayKeyName() {
        #expect(SSHKeyGenerator.defaultDisplayPath == "~/.ssh/gitrelay_ed25519")
    }

    @Test func defaultPrivateKeyPathUsesHomeSSHDirectory() {
        let home = URL(fileURLWithPath: "/Users/demo")
        #expect(SSHKeyGenerator.defaultPrivateKeyPath(homeDirectory: home) == "/Users/demo/.ssh/gitrelay_ed25519")
    }

    @Test func expandPathHandlesTildePrefix() {
        let home = URL(fileURLWithPath: "/Users/demo")
        #expect(SSHKeyGenerator.expandPath("~/.ssh/gitrelay_ed25519", homeDirectory: home) == "/Users/demo/.ssh/gitrelay_ed25519")
        #expect(SSHKeyGenerator.expandPath("/tmp/key", homeDirectory: home) == "/tmp/key")
    }

    @Test func publicKeyPathAppendsPubSuffix() {
        #expect(SSHKeyGenerator.publicKeyPath(forPrivateKeyPath: "/Users/demo/.ssh/gitrelay_ed25519") == "/Users/demo/.ssh/gitrelay_ed25519.pub")
    }

    @Test func makeSSHKeygenArgumentsUsesEd25519AndEmptyPassphraseByDefault() {
        let args = SSHKeyGenerator.makeSSHKeygenArguments(
            privateKeyPath: "/Users/demo/.ssh/gitrelay_ed25519",
            passphrase: nil
        )
        #expect(args == [
            "-t", "ed25519",
            "-f", "/Users/demo/.ssh/gitrelay_ed25519",
            "-C", "gitrelay",
            "-q",
            "-N", "",
        ])
    }

    @Test func makeSSHKeygenArgumentsIncludesProvidedPassphrase() {
        let args = SSHKeyGenerator.makeSSHKeygenArguments(
            privateKeyPath: "/Users/demo/.ssh/gitrelay_ed25519",
            passphrase: "secret"
        )
        #expect(args.contains("-N"))
        #expect(args.last == "secret")
    }

    @Test func privateKeyPermissionExpectationIsSixZeroZero() {
        #expect(SSHKeyGenerator.privateKeyPermissions == 0o600)
    }

    @Test func generateAppliesPrivateKeyPermissionsAndReturnsPublicKey() throws {
        let home = makeHomeDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let privatePath = home.appendingPathComponent(".ssh/gitrelay_ed25519").path
        let publicPath = privatePath + ".pub"
        let publicKeyContents = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAtest gitrelay\n"

        let result = try SSHKeyGenerator.generate(
            privateKeyPath: privatePath,
            homeDirectory: home,
            runProcess: { _, _ in
                try Data("PRIVATE".utf8).write(to: URL(fileURLWithPath: privatePath))
                try Data(publicKeyContents.utf8).write(to: URL(fileURLWithPath: publicPath))
            }
        )

        let privateAttributes = try FileManager.default.attributesOfItem(atPath: privatePath)
        let privatePermissions = (privateAttributes[.posixPermissions] as? NSNumber)?.uint16Value
        #expect(privatePermissions == SSHKeyGenerator.privateKeyPermissions)
        #expect(result.publicKey == publicKeyContents.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(result.privateKeyPath == privatePath)
        #expect(result.publicKeyPath == publicPath)
    }

    @Test func generateRejectsExistingKeyFiles() throws {
        let home = makeHomeDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let privatePath = home.appendingPathComponent(".ssh/gitrelay_ed25519").path
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".ssh"),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: privatePath, contents: Data())

        do {
            _ = try SSHKeyGenerator.generate(
                privateKeyPath: privatePath,
                homeDirectory: home,
                sshKeygenPath: "/usr/bin/ssh-keygen",
                runProcess: { _, _ in }
            )
            Issue.record("Expected keyAlreadyExists")
        } catch SSHKeyGeneratorError.keyAlreadyExists(let path) {
            #expect(path == privatePath)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - GitRemoteHost

struct GitRemoteHostTests {
    @Test func parsesSSHStyleRemoteHost() {
        #expect(GitRemoteHost.host(from: "git@github.com:user/repo.git") == "github.com")
        #expect(GitRemoteHost.host(from: "git@gitlab.com:org/repo.git") == "gitlab.com")
    }

    @Test func parsesHTTPSRemoteHost() {
        #expect(GitRemoteHost.host(from: "https://github.com/user/repo.git") == "github.com")
    }

    @Test func infersProviderFromHost() {
        #expect(GitRemoteHost.inferredProvider(from: "github.com") == .github)
        #expect(GitRemoteHost.inferredProvider(from: "gitlab.company.com") == .gitlab)
        #expect(GitRemoteHost.inferredProvider(from: "gitea.example.com") == .gitea)
    }

    @Test func sshKeysSettingsURLUsesProviderSpecificPaths() {
        #expect(
            GitRemoteHost.sshKeysSettingsURL(for: .github, host: "github.com").absoluteString
            == "https://github.com/settings/keys"
        )
        #expect(
            GitRemoteHost.sshKeysSettingsURL(for: .gitlab, host: "gitlab.com").absoluteString
            == "https://gitlab.com/-/user_settings/ssh_keys"
        )
        #expect(
            GitRemoteHost.sshKeysSettingsURL(for: .gitlab, host: "gitlab.company.com").absoluteString
            == "https://gitlab.company.com/-/user_settings/ssh_keys"
        )
        #expect(
            GitRemoteHost.sshKeysSettingsURL(for: .gitea, host: "gitea.example.com").absoluteString
            == "https://gitea.example.com/user/settings/keys"
        )
    }

    @Test func sshKeysSettingsURLFromRemoteURL() {
        let url = GitRemoteHost.sshKeysSettingsURL(forRemoteURL: "git@github.com:user/repo.git")
        #expect(url?.absoluteString == "https://github.com/settings/keys")
    }
}

// MARK: - GitRemoteRepoPath

struct GitRemoteRepoPathTests {
    @Test func parsesSSHGitHubURL() {
        let path = GitRemoteRepoPath.parse(from: "git@github.com:acme/widget.git")
        #expect(path?.namespace == "acme")
        #expect(path?.name == "widget")
        #expect(path?.ownerRepoPath == "acme/widget")
    }

    @Test func parsesHTTPSGitLabNestedGroup() {
        let path = GitRemoteRepoPath.parse(from: "https://gitlab.com/group/sub/repo.git")
        #expect(path?.pathWithNamespace == "group/sub/repo")
        #expect(path?.name == "repo")
    }

    @Test func rejectsEmptyURL() {
        #expect(GitRemoteRepoPath.parse(from: "   ") == nil)
    }
}

// MARK: - ReleaseMirrorDiff

struct ReleaseMirrorDiffTests {
    @Test func diffFindsMissingReleaseAndAssets() {
        let source = [
            ReleaseInfo(
                tagName: "v1.0.0",
                title: "v1",
                body: "first",
                assets: [
                    ReleaseAssetInfo(name: "app.dmg", downloadURL: URL(string: "https://example.com/a.dmg")!, size: 1, contentType: nil),
                    ReleaseAssetInfo(name: "app.tar.gz", downloadURL: URL(string: "https://example.com/a.tar.gz")!, size: 2, contentType: nil)
                ]
            ),
            ReleaseInfo(tagName: "v2.0.0", title: "v2", body: "", assets: [])
        ]
        let target = [
            ReleaseInfo(
                tagName: "v1.0.0",
                title: "v1",
                body: "first",
                assets: [
                    ReleaseAssetInfo(name: "app.dmg", downloadURL: URL(string: "https://example.com/a.dmg")!, size: 1, contentType: nil)
                ]
            )
        ]
        let resume = ReleaseMirrorResumeState()

        let plans = ReleaseMirrorDiff.plans(source: source, target: target, resume: resume)

        #expect(plans.count == 2)
        #expect(plans[0].release.tagName == "v1.0.0")
        #expect(plans[0].missingAssetNames == ["app.tar.gz"])
        #expect(plans[1].release.tagName == "v2.0.0")
        #expect(plans[1].needsCreate)
    }

    @Test func resumeSkipsCompletedAssets() {
        let source = [
            ReleaseInfo(
                tagName: "v1.0.0",
                title: "v1",
                body: "",
                assets: [
                    ReleaseAssetInfo(name: "a.bin", downloadURL: URL(string: "https://example.com/a.bin")!, size: 1, contentType: nil),
                    ReleaseAssetInfo(name: "b.bin", downloadURL: URL(string: "https://example.com/b.bin")!, size: 1, contentType: nil)
                ]
            )
        ]
        var resume = ReleaseMirrorResumeState()
        resume.markAssetCompleted(tag: "v1.0.0", assetName: "a.bin")

        let plans = ReleaseMirrorDiff.plans(source: source, target: [], resume: resume)

        #expect(plans.count == 1)
        #expect(plans[0].missingAssetNames == ["b.bin"])
    }
}

// MARK: - ReleaseMirrorResumeState

struct ReleaseMirrorResumeStateTests {
    @Test func markAssetCompletedIsIdempotent() {
        var resume = ReleaseMirrorResumeState()
        resume.markAssetCompleted(tag: "v1", assetName: "file.zip")
        resume.markAssetCompleted(tag: "v1", assetName: "file.zip")

        #expect(resume.completedAssets(for: "v1") == ["file.zip"])
    }

    @Test func resumeStoreRoundTrip() throws {
        let repoID = UUID()
        let targetID = UUID()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        Constants.setBaseDirectoryForTesting(temp)
        defer { Constants.setBaseDirectoryForTesting(nil) }

        var resume = ReleaseMirrorResumeState()
        resume.markAssetCompleted(tag: "v1", assetName: "big.tar.gz")
        try ReleaseMirrorResumeStore.saveResume(resume, repoID: repoID, targetID: targetID)

        let loaded = ReleaseMirrorResumeStore.loadResume(repoID: repoID, targetID: targetID)
        #expect(loaded.completedAssets(for: "v1") == ["big.tar.gz"])
    }
}

// MARK: - ReleaseProviderEndpoints

struct ReleaseProviderEndpointsTests {
    @Test func githubListReleasesPath() {
        let endpoint = ReleaseProviderEndpoints.githubListReleases(ownerRepo: "acme/widget", page: 2, perPage: 50)
        #expect(endpoint.path == "/repos/acme/widget/releases")
        #expect(endpoint.query.contains(URLQueryItem(name: "page", value: "2")))
        #expect(endpoint.query.contains(URLQueryItem(name: "per_page", value: "50")))
    }

    @Test func githubAssetUploadURLAddsNameQuery() {
        let template = URL(string: "https://uploads.github.com/repos/acme/widget/releases/1/assets{?name,label}")!
        let url = ReleaseProviderEndpoints.githubAssetUploadURL(from: template, fileName: "app.dmg")
        #expect(url?.absoluteString.contains("name=app.dmg") == true)
    }

    @Test func gitlabPathsArePercentEncoded() {
        let list = ReleaseProviderEndpoints.gitlabListReleases(projectPath: "group/sub/repo", page: 1, perPage: 20)
        #expect(list.path == "/projects/group%2Fsub%2Frepo/releases")

        let upload = ReleaseProviderEndpoints.gitlabUploadFile(projectPath: "group/sub/repo")
        #expect(upload.hasPrefix("/projects/"))
    }

    @Test func releaseProviderAuthUsesEnterpriseGitHubBase() {
        let base = ReleaseProviderAuth.apiBaseURL(for: "git@github.example.com:acme/repo.git", provider: .github)
        #expect(base.absoluteString == "https://github.example.com/api/v3")
    }
}

// MARK: - Archive filename template

struct ArchiveFilenameTemplateTests {
    @Test func rendersNameAndDatePlaceholders() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC

        let filename = ArchiveFilenameTemplate.render(
            template: "{name}-{date}.tar.gz",
            repoName: "My Project",
            date: date,
            calendar: calendar
        )

        #expect(filename == "My Project-2024-01-01.tar.gz")
    }

    @Test func sanitizesInvalidFilenameCharacters() {
        let filename = ArchiveFilenameTemplate.render(
            template: "{name}.bundle",
            repoName: "acme/widget:test"
        )
        #expect(filename == "acme-widget-test.bundle")
    }
}

// MARK: - Archive retention

struct ArchiveRetentionTests {
    @Test func deletesOlderArchivesBeyondRetentionCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-retention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: directory) }

        let files = ["repo-2024-01-01.tar.gz", "repo-2024-01-02.tar.gz", "repo-2024-01-03.tar.gz"]
        for (index, name) in files.enumerated() {
            let url = directory.appendingPathComponent(name)
            try Data("archive-\(index)".utf8).write(to: url)
            let timestamp = Date(timeIntervalSince1970: Double(index + 1) * 86_400)
            try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: url.path)
        }

        let stale = ArchiveRetention.archivesToDelete(
            in: directory,
            matchingPrefix: "repo-",
            keepCount: 2
        )

        #expect(stale.count == 1)
        #expect(stale[0].lastPathComponent == "repo-2024-01-01.tar.gz")
    }

    @Test func retentionDisabledWhenKeepCountIsZero() {
        let stale = ArchiveRetention.archivesToDelete(
            in: URL(fileURLWithPath: "/tmp"),
            matchingPrefix: "repo-",
            keepCount: 0
        )
        #expect(stale.isEmpty)
    }
}

// MARK: - Archive command dispatch

struct ArchiveCommandBuilderTests {
    @Test func tarGzUsesTarCreate() {
        let plan = ArchiveCommandBuilder.plan(
            format: .tarGz,
            mirrorPath: "/tmp/mirrors/repo-id",
            outputPath: "/Volumes/Backup/repo-2024-01-01.tar.gz"
        )
        #expect(plan.tool == .tar)
        #expect(plan.arguments == ["-czf", "/Volumes/Backup/repo-2024-01-01.tar.gz", "-C", "/tmp/mirrors", "repo-id"])
        #expect(plan.workingDirectory == nil)
    }

    @Test func zipUsesZipRecursiveFromParent() {
        let plan = ArchiveCommandBuilder.plan(
            format: .zip,
            mirrorPath: "/tmp/mirrors/repo-id",
            outputPath: "/Volumes/Backup/repo.zip"
        )
        #expect(plan.tool == .zip)
        #expect(plan.arguments == ["-r", "/Volumes/Backup/repo.zip", "repo-id"])
        #expect(plan.workingDirectory == "/tmp/mirrors")
    }

    @Test func gitBundleUsesGitBundleCreate() {
        let plan = ArchiveCommandBuilder.plan(
            format: .gitBundle,
            mirrorPath: "/tmp/mirrors/repo-id",
            outputPath: "/Volumes/Backup/repo.bundle"
        )
        #expect(plan.tool == .git)
        #expect(plan.arguments == ["bundle", "create", "/Volumes/Backup/repo.bundle", "--all"])
        #expect(plan.workingDirectory == "/tmp/mirrors/repo-id")
    }
}

// MARK: - Filesystem target model

struct FilesystemMirrorTargetTests {
    @Test func legacyTargetDecodesAsGitRemote() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "url": "git@github.com:user/mirror.git",
          "auth": { "sshAgent": {} },
          "enabled": true
        }
        """

        let target = try JSONDecoder().decode(MirrorTarget.self, from: Data(json.utf8))
        #expect(target.kind == .gitRemote)
        #expect(target.url == "git@github.com:user/mirror.git")
    }

    @Test func filesystemTargetRoundTrip() throws {
        let target = MirrorTarget(
            kind: .filesystem,
            enabled: true,
            filesystemPath: "/Volumes/Backup/archives",
            archiveFormat: .zip,
            filenameTemplate: "{name}-{date}.zip",
            retentionCount: 5
        )

        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(MirrorTarget.self, from: Data(data))
        #expect(decoded.kind == .filesystem)
        #expect(decoded.filesystemPath == "/Volumes/Backup/archives")
        #expect(decoded.archiveFormat == .zip)
        #expect(decoded.filenameTemplate == "{name}-{date}.zip")
        #expect(decoded.retentionCount == 5)
        #expect(decoded.displayLabel == "/Volumes/Backup/archives")
    }

    @Test func archivePrefixStripsDateFromTemplate() {
        let prefix = FilesystemArchiveService.archivePrefix(
            from: "{name}-{date}.tar.gz",
            repoName: "my-repo"
        )
        #expect(prefix == "my-repo-")
    }
}

// MARK: - Filesystem target form validation

@MainActor
struct FilesystemTargetValidationTests {
    @Test func filesystemTargetRequiresDirectory() {
        let vm = AddEditRepoViewModel()
        vm.name = "archived"
        vm.srcURL = "git@github.com:user/repo.git"
        vm.targets[0].kind = .filesystem
        vm.targets[0].filesystemPath = ""

        _ = vm.validate()
        #expect(!vm.targetErrors.isEmpty)
    }

    @Test func filesystemTargetBuildsRepoConfig() {
        let vm = AddEditRepoViewModel()
        vm.name = "archived"
        vm.srcURL = "git@github.com:user/repo.git"
        vm.targets[0].kind = .filesystem
        vm.targets[0].filesystemPath = "/Volumes/Backup/git"
        vm.targets[0].archiveFormat = .gitBundle
        vm.targets[0].retentionCount = "3"

        #expect(vm.validate())
        let repo = vm.buildRepoConfig()
        #expect(repo.targets.count == 1)
        #expect(repo.targets[0].kind == .filesystem)
        #expect(repo.targets[0].filesystemPath == "/Volumes/Backup/git")
        #expect(repo.targets[0].archiveFormat == .gitBundle)
        #expect(repo.targets[0].retentionCount == 3)
    }

    @Test func mixedGitAndFilesystemTargetsValidate() {
        let vm = AddEditRepoViewModel()
        vm.name = "mixed"
        vm.srcURL = "git@github.com:user/repo.git"
        vm.targets[0].url = "git@github.com:user/mirror.git"
        vm.addTarget()
        vm.targets[1].kind = .filesystem
        vm.targets[1].filesystemPath = "/Volumes/Backup"

        #expect(vm.validate())
        #expect(vm.buildRepoConfig().enabledTargets.count == 2)
    }
}

// MARK: - Webhook HMAC

struct WebhookHMACVerifierTests {
    @Test func githubSignatureIsDeterministicHex() {
        let payload = Data("{\"ref\":\"refs/heads/main\"}".utf8)
        let secret = "test-secret"
        let header = WebhookHMACVerifier.githubSignatureHeader(payload: payload, secret: secret)
        #expect(header.hasPrefix("sha256="))
        #expect(header.count == "sha256=".count + 64)
        #expect(
            WebhookHMACVerifier.verifyGitHubSignature(
                payload: payload,
                secret: secret,
                signatureHeader: header
            )
        )
    }

    @Test func githubSignatureRejectsTamperedPayload() {
        let secret = "test-secret"
        let good = Data("{\"ref\":\"refs/heads/main\"}".utf8)
        let header = WebhookHMACVerifier.githubSignatureHeader(payload: good, secret: secret)
        let bad = Data("{\"ref\":\"refs/heads/other\"}".utf8)
        #expect(
            !WebhookHMACVerifier.verifyGitHubSignature(
                payload: bad,
                secret: secret,
                signatureHeader: header
            )
        )
    }

    @Test func githubSignatureRejectsWrongSecret() {
        let payload = Data("{}".utf8)
        let header = WebhookHMACVerifier.githubSignatureHeader(payload: payload, secret: "a")
        #expect(
            !WebhookHMACVerifier.verifyGitHubSignature(
                payload: payload,
                secret: "b",
                signatureHeader: header
            )
        )
    }

    @Test func gitlabTokenEquality() {
        #expect(WebhookHMACVerifier.verifyGitLabToken(secret: "s3cret", tokenHeader: "s3cret"))
        #expect(!WebhookHMACVerifier.verifyGitLabToken(secret: "s3cret", tokenHeader: "nope"))
        #expect(!WebhookHMACVerifier.verifyGitLabToken(secret: "s3cret", tokenHeader: nil))
    }

    @Test func verifyPrefersGitHubHeaderWhenPresent() {
        let payload = Data("hi".utf8)
        let secret = "abc"
        let sig = WebhookHMACVerifier.githubSignatureHeader(payload: payload, secret: secret)
        #expect(
            WebhookHMACVerifier.verify(
                payload: payload,
                secret: secret,
                githubSignatureHeader: sig,
                gitlabTokenHeader: "wrong"
            )
        )
        #expect(
            !WebhookHMACVerifier.verify(
                payload: payload,
                secret: secret,
                githubSignatureHeader: "sha256=deadbeef",
                gitlabTokenHeader: secret
            )
        )
    }

    @Test func generateSecretIsNonEmpty() {
        let a = WebhookHMACVerifier.generateSecret()
        let b = WebhookHMACVerifier.generateSecret()
        #expect(!a.isEmpty)
        #expect(!b.isEmpty)
        #expect(a != b)
    }
}

// MARK: - Webhook HTTP routing

struct WebhookRouteTests {
    @Test func parsesHookPath() {
        #expect(WebhookRoute.parse(method: "POST", path: "/hook/abc-123") == .hook(id: "abc-123"))
        #expect(WebhookRoute.parse(method: "POST", path: "/hook/abc-123/") == .hook(id: "abc-123"))
        #expect(WebhookRoute.parse(method: "POST", path: "/hook/abc-123?x=1") == .hook(id: "abc-123"))
    }

    @Test func rejectsNestedOrEmptyHookPath() {
        #expect(WebhookRoute.parse(method: "POST", path: "/hook/") == .notFound)
        #expect(WebhookRoute.parse(method: "POST", path: "/hook/a/b") == .notFound)
        #expect(WebhookRoute.parse(method: "POST", path: "/hooks/abc") == .notFound)
    }

    @Test func parsesHealth() {
        #expect(WebhookRoute.parse(method: "GET", path: "/health") == .health)
        #expect(WebhookRoute.parse(method: "GET", path: "/healthz") == .health)
    }
}

struct WebhookHTTPParserTests {
    @Test func parsesPostWithBodyAndHeaders() throws {
        let body = "{\"ref\":\"refs/heads/main\"}"
        let raw = Data(
            """
            POST /hook/deadbeef HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Type: application/json\r
            X-GitHub-Event: push\r
            Content-Length: \(body.utf8.count)\r
            \r
            \(body)
            """.utf8
        )
        let request = try #require(WebhookHTTPParser.parse(raw))
        #expect(request.method == "POST")
        #expect(request.path == "/hook/deadbeef")
        #expect(request.header("X-GitHub-Event") == "push")
        #expect(String(data: request.body, encoding: .utf8) == body)
    }

    @Test func returnsNilWhenBodyIncomplete() {
        let raw = Data("POST /hook/x HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort".utf8)
        #expect(WebhookHTTPParser.parse(raw) == nil)
    }
}

// MARK: - Webhook push → sync mapping

struct WebhookPushMapperTests {
    private let repoID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func targets(enabled: Bool = true) -> [WebhookPushMapper.HookTarget] {
        [
            .init(
                repoID: repoID,
                pathID: WebhookPushMapper.pathID(for: repoID),
                enabled: enabled
            )
        ]
    }

    private func signedPushRequest(
        pathID: String,
        secret: String,
        event: String = "push",
        body: String = "{\"ref\":\"refs/heads/main\",\"commits\":[]}"
    ) -> WebhookHTTPRequest {
        let data = Data(body.utf8)
        let signature = WebhookHMACVerifier.githubSignatureHeader(payload: data, secret: secret)
        return WebhookHTTPRequest(
            method: "POST",
            path: "/hook/\(pathID)",
            headers: [
                "X-GitHub-Event": event,
                "X-Hub-Signature-256": signature,
                "Content-Type": "application/json"
            ],
            body: data
        )
    }

    @Test func pushEventMapsToAcceptedSync() {
        let secret = "hook-secret"
        let request = signedPushRequest(
            pathID: WebhookPushMapper.pathID(for: repoID),
            secret: secret
        )
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(),
            secretForRepo: { $0 == repoID ? secret : nil }
        )
        #expect(result == .acceptedSync(repoID: repoID))
        #expect(result.shouldTriggerSync)
        #expect(result.syncRepoID == repoID)
        #expect(result.httpResponse.statusCode == 202)
    }

    @Test func pingDoesNotTriggerSync() {
        let secret = "hook-secret"
        let request = signedPushRequest(
            pathID: WebhookPushMapper.pathID(for: repoID),
            secret: secret,
            event: "ping",
            body: "{}"
        )
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(),
            secretForRepo: { _ in secret }
        )
        #expect(result == .pingAcknowledged)
        #expect(!result.shouldTriggerSync)
    }

    @Test func invalidSignatureIsUnauthorized() {
        let request = signedPushRequest(
            pathID: WebhookPushMapper.pathID(for: repoID),
            secret: "correct"
        )
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(),
            secretForRepo: { _ in "wrong" }
        )
        #expect(result == .unauthorized)
    }

    @Test func unknownPathIsNotFound() {
        let secret = "s"
        let request = signedPushRequest(pathID: "missing-id", secret: secret)
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(),
            secretForRepo: { _ in secret }
        )
        #expect(result == .notFound)
    }

    @Test func disabledRepoIsIgnored() {
        let secret = "s"
        let request = signedPushRequest(
            pathID: WebhookPushMapper.pathID(for: repoID),
            secret: secret
        )
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(enabled: false),
            secretForRepo: { _ in secret }
        )
        #expect(result == .ignored(reason: "webhook disabled for repo"))
        #expect(!result.shouldTriggerSync)
    }

    @Test func getHookIsMethodNotAllowed() {
        let request = WebhookHTTPRequest(
            method: "GET",
            path: "/hook/\(WebhookPushMapper.pathID(for: repoID))",
            headers: [:],
            body: Data()
        )
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(),
            secretForRepo: { _ in "s" }
        )
        #expect(result == .methodNotAllowed)
    }

    @Test func gitlabPushHookAccepted() {
        let secret = "gl-secret"
        let body = Data("{\"ref\":\"refs/heads/main\"}".utf8)
        let request = WebhookHTTPRequest(
            method: "POST",
            path: "/hook/\(WebhookPushMapper.pathID(for: repoID))",
            headers: [
                "X-Gitlab-Event": "Push Hook",
                "X-Gitlab-Token": secret
            ],
            body: body
        )
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets(),
            secretForRepo: { _ in secret }
        )
        #expect(result == .acceptedSync(repoID: repoID))
    }
}

@MainActor
struct WebhookSyncTriggerTests {
    @Test func handleWebhookRequestQueuesSyncIndependentlyOfFrequency() {
        let suite = "gitrelay.tests.webhook.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults)
        )
        let repoID = UUID()
        let secret = "unit-test-secret"
        vm.webhookSecretProvider = { $0 == repoID ? secret : nil }

        let repo = RepoConfig(
            id: repoID,
            name: "hooked",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            frequency: .manual,
            webhookEnabled: true
        )
        vm.addRepo(repo)

        let body = Data("{\"ref\":\"refs/heads/main\"}".utf8)
        let signature = WebhookHMACVerifier.githubSignatureHeader(payload: body, secret: secret)
        let request = WebhookHTTPRequest(
            method: "POST",
            path: "/hook/\(repo.webhookPathID)",
            headers: [
                "X-GitHub-Event": "push",
                "X-Hub-Signature-256": signature
            ],
            body: body
        )

        let response = vm.handleWebhookRequest(request)
        #expect(response.statusCode == 202)
        #expect(vm.inProgressSyncIDs.contains(repoID) || vm.statuses[repoID] == .syncing)
        vm.cancelSync(repoID: repoID)
    }
}

struct WebhookURLTemplateTests {
    @Test func localAndPublicURLs() {
        let id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        #expect(
            WebhookURLTemplate.localURL(port: 4567, pathID: id)
                == "http://127.0.0.1:4567/hook/\(id)"
        )
        #expect(
            WebhookURLTemplate.publicURL(baseURL: "https://abc.trycloudflare.com/", pathID: id)
                == "https://abc.trycloudflare.com/hook/\(id)"
        )
    }

    @Test func displayFallsBackToModeTemplate() {
        let prefs = WebhookPreferences(
            listenerEnabled: true,
            exposureMode: .cloudflareTunnel,
            publicBaseURL: ""
        )
        let url = WebhookURLTemplate.displayURL(preferences: prefs, port: 9, pathID: "x")
        #expect(url.contains("cloudflare-tunnel-host"))
        #expect(url.hasSuffix("/hook/x"))
    }
}

struct WebhookTunnelToolDetectorTests {
    @Test func detectsExecutableViaInjectedProbe() {
        #expect(
            WebhookTunnelToolDetector.isCloudflaredAvailable { path in
                path.hasSuffix("/cloudflared")
            }
        )
        #expect(
            !WebhookTunnelToolDetector.isTailscaleAvailable { _ in false }
        )
    }
}

@MainActor
struct WebhookPreferencesStoreTests {
    @Test func defaultsAreOff() {
        let suite = "gitrelay.tests.webhook-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebhookPreferencesStore(defaults: defaults)
        #expect(store.preferences.listenerEnabled == false)
        #expect(store.preferences.exposureMode == .off)
    }

    @Test func persistsExposureMode() {
        let suite = "gitrelay.tests.webhook-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebhookPreferencesStore(defaults: defaults)
        var prefs = store.preferences
        prefs.listenerEnabled = true
        prefs.exposureMode = .tailscaleFunnel
        prefs.publicBaseURL = "https://host.example/"
        store.preferences = prefs

        let reloaded = WebhookPreferencesStore(defaults: defaults)
        #expect(reloaded.preferences.listenerEnabled)
        #expect(reloaded.preferences.exposureMode == .tailscaleFunnel)
        #expect(reloaded.preferences.publicBaseURL == "https://host.example")
    }
}

struct ProviderTokenWebhookScopeTests {
    @Test func webhookRegistrationRequiresAdminRepoHook() {
        let missing = ProviderTokenScope.validate(
            grantedScopes: ["public_repo"],
            usage: .webhookRegistration(provider: .github)
        )
        #expect(!missing.isFullyAuthorized)
        #expect(missing.missingRequiredScopes == ["admin:repo_hook"])

        let ok = ProviderTokenScope.validate(
            grantedScopes: ["repo"],
            usage: .webhookRegistration(provider: .github)
        )
        #expect(ok.isFullyAuthorized)
    }

    @Test func disclosureTextIsPresent() {
        let text = ProviderTokenUsage.webhookRegistration(provider: .github).disclosureText
        #expect(text?.contains("admin:repo_hook") == true)
    }
}

@MainActor
struct AddEditRepoWebhookTests {
    @Test func buildRepoConfigIncludesWebhookFlag() {
        let vm = AddEditRepoViewModel()
        vm.name = "w"
        vm.srcURL = "git@github.com:user/repo.git"
        vm.targets[0].url = "git@github.com:user/mirror.git"
        vm.webhookEnabled = true
        #expect(vm.validate())
        #expect(vm.buildRepoConfig().webhookEnabled)
    }

    @Test func loadsWebhookEnabledFromExistingRepo() {
        let repo = RepoConfig(
            name: "w",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            webhookEnabled: true
        )
        let vm = AddEditRepoViewModel(editing: repo)
        #expect(vm.webhookEnabled)
    }
}

// MARK: - ProviderAccount

struct ProviderAccountTests {
    @Test func normalizeLabelAcceptsFriendlyNames() {
        #expect(ProviderAccount.normalizeLabel("Work") == "work")
        #expect(ProviderAccount.normalizeLabel(" personal ") == "personal")
        #expect(ProviderAccount.normalizeLabel("my_team-2") == "my_team-2")
    }

    @Test func normalizeLabelRejectsInvalidInput() {
        #expect(ProviderAccount.normalizeLabel("") == nil)
        #expect(ProviderAccount.normalizeLabel("   ") == nil)
        #expect(ProviderAccount.normalizeLabel("bad/name") == nil)
        #expect(ProviderAccount.normalizeLabel(String(repeating: "a", count: 33)) == nil)
    }

    @Test func accountIdentityCombinesProviderAndLabel() {
        let account = ProviderAccount(provider: .github, label: "work")
        #expect(account.id == "github-work")
        #expect(ProviderAccount.id(provider: .gitlab, label: "default") == "gitlab-default")
    }
}

struct BrowseRemoteAccountSelectionTests {
    @Test func validatedNewLabelRejectsDuplicates() {
        #expect(BrowseRemoteAccountSelection.validatedNewLabel("Work", existing: ["work"]) == nil)
        #expect(BrowseRemoteAccountSelection.validatedNewLabel("Personal", existing: ["default"]) == "personal")
    }

    @Test func cannotDeleteLastAccount() {
        #expect(!BrowseRemoteAccountSelection.canDeleteAccount(accountCount: 1))
        #expect(BrowseRemoteAccountSelection.canDeleteAccount(accountCount: 2))
    }

    @Test func selectedLabelAfterDeletePrefersDefault() {
        let next = BrowseRemoteAccountSelection.selectedLabelAfterDelete(
            deleted: "work",
            current: "work",
            remaining: ["default", "personal"]
        )
        #expect(next == ProviderAccount.defaultLabel)
    }

    @Test func selectedLabelAfterDeleteKeepsCurrentWhenNotDeleted() {
        let next = BrowseRemoteAccountSelection.selectedLabelAfterDelete(
            deleted: "work",
            current: "personal",
            remaining: ["default", "personal"]
        )
        #expect(next == "personal")
    }
}

struct ProviderTokenStoreMigrationTests {
    @Test func legacyTagMigratesToDefaultAccountTag() throws {
        let provider = GitProvider.github
        let legacy = ProviderTokenStore.legacyTag(for: provider)
        let migrated = ProviderTokenStore.tag(for: provider, accountLabel: ProviderAccount.defaultLabel)
        defer {
            try? KeychainService.deleteToken(tag: legacy)
            try? KeychainService.deleteToken(tag: migrated)
        }

        try KeychainService.saveToken("legacy-token", tag: legacy)
        ProviderTokenStore.migrateLegacyTokenIfNeeded(for: provider)

        #expect(try KeychainService.loadToken(tag: migrated) == "legacy-token")
        #expect((try? KeychainService.loadToken(tag: legacy)) == nil)
    }

    @Test func namespacedTagIncludesProviderAndAccount() {
        #expect(ProviderTokenStore.tag(for: .gitea, accountLabel: "work") == "provider-api-gitea-work")
        #expect(ProviderTokenStore.legacyTag(for: .gitea) == "provider-api-gitea")
    }
}

struct ProviderAccountStoreTests {
    @Test func migrateLegacyHostIntoDefaultAccount() {
        let suite = "gitrelay.tests.provider-accounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("https://gitlab.company.com", forKey: "BrowseRemoteRepo.gitlabHost")
        ProviderAccountStore.migrateIfNeeded(defaults: defaults)

        #expect(
            ProviderAccountStore.host(for: .gitlab, label: ProviderAccount.defaultLabel, defaults: defaults)
                == "https://gitlab.company.com"
        )
        #expect(defaults.string(forKey: "BrowseRemoteRepo.gitlabHost") == nil)
    }

    @Test func addSwitchAndDeleteAccounts() throws {
        let suite = "gitrelay.tests.provider-accounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        ProviderAccountStore.migrateIfNeeded(defaults: defaults)
        _ = try ProviderAccountStore.addAccount(label: "Work", for: .github, defaults: defaults)
        ProviderAccountStore.setSelectedLabel("work", for: .github, defaults: defaults)

        #expect(ProviderAccountStore.selectedLabel(for: .github, defaults: defaults) == "work")
        #expect(ProviderAccountStore.accountLabels(for: .github, defaults: defaults).contains("work"))

        try ProviderAccountStore.removeAccount(label: "work", for: .github, defaults: defaults)
        #expect(!ProviderAccountStore.accountLabels(for: .github, defaults: defaults).contains("work"))
        #expect(ProviderAccountStore.selectedLabel(for: .github, defaults: defaults) == ProviderAccount.defaultLabel)
    }
}

@MainActor
struct BrowseRemoteRepoViewModelAccountTests {
    @Test func switchingAccountsRestoresSeparateTokensAndHosts() throws {
        let suite = "gitrelay.tests.browse-vm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            for provider in GitProvider.allCases {
                for label in ["default", "work"] {
                    try? KeychainService.deleteToken(
                        tag: ProviderTokenStore.tag(for: provider, accountLabel: label)
                    )
                }
                try? KeychainService.deleteToken(tag: ProviderTokenStore.legacyTag(for: provider))
            }
        }

        ProviderAccountStore.migrateIfNeeded(defaults: defaults)
        _ = try ProviderAccountStore.addAccount(label: "Work", for: .gitlab, defaults: defaults)

        try ProviderTokenStore.save(token: "default-token", provider: .gitlab, accountLabel: "default")
        try ProviderTokenStore.save(token: "work-token", provider: .gitlab, accountLabel: "work")
        ProviderAccountStore.setHost("https://gitlab.com", for: .gitlab, label: "default", defaults: defaults)
        ProviderAccountStore.setHost("https://gitlab.company.com", for: .gitlab, label: "work", defaults: defaults)

        let vm = BrowseRemoteRepoViewModel(defaults: defaults)
        vm.provider = .gitlab
        vm.refreshSourceAccounts()

        vm.selectSourceAccount("default")
        #expect(vm.token == "default-token")
        #expect(vm.gitlabHost == "https://gitlab.com")

        vm.selectSourceAccount("work")
        #expect(vm.token == "work-token")
        #expect(vm.gitlabHost == "https://gitlab.company.com")
    }
}

// MARK: - Localization

struct LocalizationTests {
    @Test func syncFrequencyDisplayNamesAreEnglishInDefaultLocale() {
        #expect(SyncFrequency.manual.displayName == "Manual")
        #expect(SyncFrequency.min15.displayName == "Every 15 Minutes")
        #expect(SyncFrequency.min30.displayName == "Every 30 Minutes")
        #expect(SyncFrequency.hour1.displayName == "Hourly")
        #expect(SyncFrequency.day1.displayName == "Daily")
    }

    @Test func verificationFrequencyDisplayNamesAreEnglishInDefaultLocale() {
        #expect(VerificationFrequency.manual.displayName == "Manual")
        #expect(VerificationFrequency.day1.displayName == "Daily")
        #expect(VerificationFrequency.week1.displayName == "Weekly")
        #expect(VerificationFrequency.month1.displayName == "Monthly")
    }

    @Test func syncFrequencyRawValuesRemainChineseForCodableCompatibility() {
        #expect(SyncFrequency.manual.rawValue == "手动")
        #expect(SyncFrequency.min15.rawValue == "每 15 分钟")
    }

    @Test func destructivePushCopyUsesLocalizedEnglishDefaults() {
        let plan = DestructivePushPlan(deletedRefs: ["a"], forcedUpdateRefs: ["main"])
        #expect(plan.summary == "1 deletions, 1 forced updates")
        #expect(plan.confirmationPrompt.contains("Continue?"))
        #expect(DestructivePushPolicy.strict.displayName == "Strict Protection")
        #expect(DestructivePushPolicy.auto.displayName == "Run Automatically")
    }

    @Test func pauseReasonMessagesAreLocalizedEnglishDefaults() {
        #expect(SyncPauseReason.quietHours.displayMessage == "Quiet hours")
        #expect(SyncPauseReason.lowPowerMode.displayMessage.contains("Low Power Mode"))
        #expect(SyncPauseReason.expensiveNetwork.displayMessage.contains("expensive"))
    }
}

// MARK: - Sensitive action policy (#19)

struct SensitiveActionPolicyTests {
    @Test func defaultsRequireAuthenticationForAllHighRiskActions() {
        let policy = SensitiveActionPolicy(requireBiometricForSensitive: true)
        #expect(policy.requiresAuthentication(for: .revealToken))
        #expect(policy.requiresAuthentication(for: .deleteRepository))
        #expect(policy.requiresAuthentication(for: .changeTargetHost(
            originalURL: "git@github.com:org/a.git",
            newURL: "git@gitlab.com:org/a.git"
        )))
    }

    @Test func disabledPreferenceSkipsAuthentication() {
        let policy = SensitiveActionPolicy(requireBiometricForSensitive: false)
        #expect(!policy.requiresAuthentication(for: .revealToken))
        #expect(!policy.requiresAuthentication(for: .deleteRepository))
        #expect(!policy.requiresAuthentication(for: .changeTargetHost(
            originalURL: "git@github.com:org/a.git",
            newURL: "git@gitlab.com:org/a.git"
        )))
    }

    @Test func sameHostTargetURLChangeDoesNotRequireAuthentication() {
        let policy = SensitiveActionPolicy(requireBiometricForSensitive: true)
        #expect(!policy.requiresAuthentication(for: .changeTargetHost(
            originalURL: "git@github.com:org/a.git",
            newURL: "https://github.com/org/b.git"
        )))
        #expect(!policy.requiresAuthentication(for: .changeTargetHost(
            originalURL: "git@github.com:org/a.git",
            newURL: "git@github.com:org/a.git"
        )))
    }

    @Test func invalidURLsDoNotRequireAuthentication() {
        let policy = SensitiveActionPolicy(requireBiometricForSensitive: true)
        #expect(!policy.requiresAuthentication(for: .changeTargetHost(
            originalURL: "not-a-url",
            newURL: "git@gitlab.com:org/a.git"
        )))
    }
}

@MainActor
struct SecurityPreferencesStoreTests {
    @Test func loadsDefaultRequireBiometricWhenKeyMissing() {
        let suite = "gitrelay.tests.security-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SecurityPreferencesStore(defaults: defaults)
        #expect(store.preferences.requireBiometricForSensitive == true)
    }

    @Test func persistsAndReloadsToggle() {
        let suite = "gitrelay.tests.security-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SecurityPreferencesStore(defaults: defaults)
        store.preferences.requireBiometricForSensitive = false

        let reloaded = SecurityPreferencesStore(defaults: defaults)
        #expect(reloaded.preferences.requireBiometricForSensitive == false)
    }

    @Test func resetToDefaultsRestoresOnByDefault() {
        let suite = "gitrelay.tests.security-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SecurityPreferencesStore(defaults: defaults)
        store.preferences.requireBiometricForSensitive = false
        store.resetToDefaults()
        #expect(store.preferences.requireBiometricForSensitive == true)
    }
}

// MARK: - AppBehaviorPreferencesStore / AppLifecyclePolicy

struct AppLifecyclePolicyTests {
    @Test func keepInMenuBarUsesAccessoryAndDoesNotQuit() {
        #expect(AppLifecyclePolicy.shouldSwitchToAccessoryAfterLastWindowCloses(keepInMenuBar: true))
        #expect(!AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(keepInMenuBar: true))
    }

    @Test func disableKeepInMenuBarQuitsAfterLastWindow() {
        #expect(!AppLifecyclePolicy.shouldSwitchToAccessoryAfterLastWindowCloses(keepInMenuBar: false))
        #expect(AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(keepInMenuBar: false))
    }

    @Test func visibleTitledWindowBlocksAccessoryDecision() {
        #expect(
            AppLifecyclePolicy.hasVisibleTitledWindow([
                (isTitled: true, isVisible: true),
                (isTitled: false, isVisible: true),
            ])
        )
        #expect(
            !AppLifecyclePolicy.hasVisibleTitledWindow([
                (isTitled: true, isVisible: false),
                (isTitled: false, isVisible: true),
            ])
        )
    }

    @Test func settingsSidebarPanesCoverAllGroups() {
        #expect(SettingsPane.allCases.map(\.rawValue) == [
            "security",
            "notifications",
            "schedule",
            "webhook",
            "cache",
            "configuration",
        ])
    }
}

@MainActor
struct AppBehaviorPreferencesStoreTests {
    @Test func loadsDefaultKeepInMenuBarWhenKeyMissing() {
        let suite = "gitrelay.tests.app-behavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppBehaviorPreferencesStore(defaults: defaults)
        #expect(store.preferences.keepInMenuBarWhenMainWindowCloses == true)
    }

    @Test func persistsAndReloadsKeepInMenuBarToggle() {
        let suite = "gitrelay.tests.app-behavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppBehaviorPreferencesStore(defaults: defaults)
        store.preferences.keepInMenuBarWhenMainWindowCloses = false

        let reloaded = AppBehaviorPreferencesStore(defaults: defaults)
        #expect(reloaded.preferences.keepInMenuBarWhenMainWindowCloses == false)
    }

    @Test func resetToDefaultsRestoresKeepInMenuBarOn() {
        let suite = "gitrelay.tests.app-behavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppBehaviorPreferencesStore(defaults: defaults)
        store.preferences.keepInMenuBarWhenMainWindowCloses = false
        store.resetToDefaults()
        #expect(store.preferences.keepInMenuBarWhenMainWindowCloses == true)
    }
}

// MARK: - WindowLayoutStore

@MainActor
struct WindowLayoutStoreTests {
    @Test func loadsDefaultsWhenKeysMissing() {
        let suite = "gitrelay.tests.window-layout.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WindowLayoutStore(defaults: defaults)
        #expect(store.selectedRepoID == nil)
        #expect(store.detailTab == .overview)
        #expect(store.sidebarWidth == DesignTokens.Layout.sidebarIdealWidth)
    }

    @Test func persistsAndReloadsSelectionTabAndSidebarWidth() {
        let suite = "gitrelay.tests.window-layout.roundtrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let repoID = UUID()
        let store = WindowLayoutStore(defaults: defaults)
        store.selectedRepoID = repoID
        store.detailTab = .releases
        store.sidebarWidth = 280

        let reloaded = WindowLayoutStore(defaults: defaults)
        #expect(reloaded.selectedRepoID == repoID)
        #expect(reloaded.detailTab == .releases)
        #expect(reloaded.sidebarWidth == 280)
    }

    @Test func reconcileSelectionClearsMissingRepoID() {
        let suite = "gitrelay.tests.window-layout.ghost.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let gone = UUID()
        let kept = UUID()
        let store = WindowLayoutStore(defaults: defaults)
        store.selectedRepoID = gone

        store.reconcileSelection(withExistingIDs: [kept])
        #expect(store.selectedRepoID == nil)

        let reloaded = WindowLayoutStore(defaults: defaults)
        #expect(reloaded.selectedRepoID == nil)
    }

    @Test func reconcileSelectionKeepsExistingRepoID() {
        let suite = "gitrelay.tests.window-layout.keep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let repoID = UUID()
        let store = WindowLayoutStore(defaults: defaults)
        store.selectedRepoID = repoID

        store.reconcileSelection(withExistingIDs: [repoID])
        #expect(store.selectedRepoID == repoID)
    }

    @Test func invalidStoredTabFallsBackToOverview() {
        let suite = "gitrelay.tests.window-layout.bad-tab.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("not-a-tab", forKey: "WindowLayout.detailTab")
        let store = WindowLayoutStore(defaults: defaults)
        #expect(store.detailTab == .overview)
    }

    @Test func invalidStoredRepoIDStringClearsSelection() {
        let suite = "gitrelay.tests.window-layout.bad-id.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("not-a-uuid", forKey: "WindowLayout.selectedRepoID")
        let store = WindowLayoutStore(defaults: defaults)
        #expect(store.selectedRepoID == nil)
    }

    @Test func sidebarWidthClampsToDesignTokenRange() {
        let suite = "gitrelay.tests.window-layout.clamp.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WindowLayoutStore(defaults: defaults)
        store.layout = WindowLayout(
            selectedRepoID: nil,
            detailTab: .overview,
            sidebarWidth: 10
        )
        #expect(store.sidebarWidth == DesignTokens.Layout.sidebarMinWidth)

        store.layout = WindowLayout(
            selectedRepoID: nil,
            detailTab: .overview,
            sidebarWidth: 999
        )
        #expect(store.sidebarWidth == DesignTokens.Layout.sidebarMaxWidth)
    }

    @Test func sidebarWidthSetterIgnoresOutOfRangeProbes() {
        let suite = "gitrelay.tests.window-layout.ignore-probe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WindowLayoutStore(defaults: defaults)
        store.sidebarWidth = 260
        store.sidebarWidth = 0
        #expect(store.sidebarWidth == 260)
        store.sidebarWidth = 9_999
        #expect(store.sidebarWidth == 260)
    }

    @Test func deleteRepoClearsPersistedSelectionForRemovedID() {
        let suite = "gitrelay.tests.window-layout.delete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-window-layout-delete-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        defer { try? FileManager.default.removeItem(at: base) }

        let layoutStore = WindowLayoutStore(defaults: defaults)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            windowLayoutStore: layoutStore
        )
        let repoID = UUID()
        vm.addRepo(
            RepoConfig(
                id: repoID,
                name: "doomed",
                srcURL: "git@github.com:user/doomed.git",
                dstURL: "git@github.com:user/doomed-mirror.git",
                frequency: .manual
            )
        )
        layoutStore.selectedRepoID = repoID

        vm.deleteRepo(id: repoID)

        #expect(layoutStore.selectedRepoID == nil)
        let reloaded = WindowLayoutStore(defaults: defaults)
        #expect(reloaded.selectedRepoID == nil)
    }
}

struct WindowLayoutModelTests {
    @Test func reconciledClearsGhostSelection() {
        let ghost = UUID()
        let layout = WindowLayout(
            selectedRepoID: ghost,
            detailTab: .releases,
            sidebarWidth: 260
        )
        let reconciled = layout.reconciled(withExistingIDs: [UUID()])
        #expect(reconciled.selectedRepoID == nil)
        #expect(reconciled.detailTab == .releases)
        #expect(reconciled.sidebarWidth == 260)
    }

    @Test func clampedSidebarWidthRespectsMinMax() {
        #expect(
            WindowLayout.clampedSidebarWidth(0)
                == Double(DesignTokens.Layout.sidebarMinWidth)
        )
        #expect(
            WindowLayout.clampedSidebarWidth(10_000)
                == Double(DesignTokens.Layout.sidebarMaxWidth)
        )
        #expect(WindowLayout.clampedSidebarWidth(240) == 240)
    }
}

@MainActor
struct LoginItemControllerTests {
    @Test func enableFailureLeavesToggleOffAndSurfacesError() {
        let stub = StubLoginItemService(isEnabled: false, requiresApproval: false)
        stub.nextError = LoginItemServiceError.requiresApproval
        let controller = LoginItemController(service: stub)

        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(controller.lastErrorMessage != nil)
    }

    @Test func successfulEnableReflectsServiceState() {
        let stub = StubLoginItemService(isEnabled: false, requiresApproval: false)
        let controller = LoginItemController(service: stub)

        controller.setEnabled(true)

        #expect(controller.isEnabled == true)
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func requiresApprovalAfterRegisterDoesNotLie() {
        let stub = StubLoginItemService(isEnabled: false, requiresApproval: false)
        stub.enableLeavesRequiresApproval = true
        let controller = LoginItemController(service: stub)

        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(controller.requiresApproval == true)
        #expect(controller.lastErrorMessage != nil)
    }
}

@MainActor
final class StubLoginItemService: LoginItemManaging {
    var isEnabled: Bool
    var requiresApproval: Bool
    var nextError: Error?
    var enableLeavesRequiresApproval = false

    init(isEnabled: Bool, requiresApproval: Bool) {
        self.isEnabled = isEnabled
        self.requiresApproval = requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        if enabled && enableLeavesRequiresApproval {
            isEnabled = false
            requiresApproval = true
            return
        }
        isEnabled = enabled
        requiresApproval = false
    }
}

struct BiometricGateTests {
    @Test func allowsActionWhenPolicyDoesNotRequireAuthentication() async {
        let gate = BiometricGate(
            policy: SensitiveActionPolicy(requireBiometricForSensitive: false),
            authenticator: StubBiometricAuthenticator(result: false)
        )
        #expect(await gate.authorize(action: .revealToken))
    }

    @Test func abortsWhenAuthenticationFails() async {
        let gate = BiometricGate(
            policy: SensitiveActionPolicy(requireBiometricForSensitive: true),
            authenticator: StubBiometricAuthenticator(result: false)
        )
        #expect(await gate.authorize(action: .deleteRepository) == false)
    }

    @Test func proceedsWhenAuthenticationSucceeds() async {
        let authenticator = StubBiometricAuthenticator(result: true)
        let gate = BiometricGate(
            policy: SensitiveActionPolicy(requireBiometricForSensitive: true),
            authenticator: authenticator
        )
        #expect(await gate.authorize(action: .revealToken))
        #expect(authenticator.lastReason?.contains("token") == true)
    }
}

@MainActor
struct AddEditRepoHostChangeDetectionTests {
    @Test func detectsGitRemoteTargetHostChangesOnly() {
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let original = RepoConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "demo",
            srcURL: "git@github.com:org/src.git",
            targets: [
                MirrorTarget(
                    id: targetID,
                    kind: .gitRemote,
                    url: "git@github.com:org/dst.git",
                    auth: .sshAgent,
                    enabled: true
                )
            ],
            srcAuth: .sshAgent,
            frequency: .manual,
            destructivePushPolicy: .strict,
            defaultBranch: "main",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let vm = AddEditRepoViewModel(editing: original)
        vm.targets[0].url = "git@gitlab.com:org/dst.git"

        let changes = vm.gitRemoteTargetHostChanges(comparedTo: original)
        #expect(changes.count == 1)
        #expect(changes[0].originalURL == "git@github.com:org/dst.git")
        #expect(changes[0].newURL == "git@gitlab.com:org/dst.git")
    }

    @Test func ignoresSameHostPathChanges() {
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let original = RepoConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "demo",
            srcURL: "git@github.com:org/src.git",
            targets: [
                MirrorTarget(
                    id: targetID,
                    kind: .gitRemote,
                    url: "git@github.com:org/dst.git",
                    auth: .sshAgent,
                    enabled: true
                )
            ],
            srcAuth: .sshAgent,
            frequency: .manual,
            destructivePushPolicy: .strict,
            defaultBranch: "main",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let vm = AddEditRepoViewModel(editing: original)
        vm.targets[0].url = "https://github.com/other/dst.git"

        #expect(vm.gitRemoteTargetHostChanges(comparedTo: original).isEmpty)
    }
}

// MARK: - Mirror cache quota

struct MirrorCacheManagerTests {
    private let repoA = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let repoB = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let repoC = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    @Test func nilQuotaIsUnlimited() {
        #expect(MirrorCacheManager.quotaLimitBytes(for: nil) == nil)
        #expect(!MirrorCacheManager.isOverQuota(usageBytes: 999_999_999_999, quotaGB: nil))
    }

    @Test func quotaLimitConvertsGigabytesToBytes() {
        #expect(MirrorCacheManager.quotaLimitBytes(for: 50) == 50 * MirrorCacheManager.bytesPerGB)
        #expect(MirrorCacheManager.isOverQuota(usageBytes: 51 * MirrorCacheManager.bytesPerGB, quotaGB: 50))
        #expect(!MirrorCacheManager.isOverQuota(usageBytes: 50 * MirrorCacheManager.bytesPerGB, quotaGB: 50))
    }

    @Test func lruSortsOldestAccessFirstWithStableTieBreak() {
        let older = MirrorCacheEntry(repoID: repoB, lastAccessedAt: Date(timeIntervalSince1970: 100), sizeBytes: 10)
        let newer = MirrorCacheEntry(repoID: repoA, lastAccessedAt: Date(timeIntervalSince1970: 200), sizeBytes: 10)
        let tiedOlderID = MirrorCacheEntry(repoID: repoA, lastAccessedAt: Date(timeIntervalSince1970: 100), sizeBytes: 10)
        let tiedNewerID = MirrorCacheEntry(repoID: repoC, lastAccessedAt: Date(timeIntervalSince1970: 100), sizeBytes: 10)

        #expect(MirrorCacheManager.lruSorted([newer, older]).map(\.repoID) == [repoB, repoA])
        #expect(MirrorCacheManager.lruSorted([tiedNewerID, tiedOlderID]).map(\.repoID) == [repoA, repoC])
    }

    @Test func cleanupPlanUsesGCThenDeleteForOldestRepo() {
        let entries = [
            MirrorCacheEntry(repoID: repoA, lastAccessedAt: Date(timeIntervalSince1970: 300), sizeBytes: 40),
            MirrorCacheEntry(repoID: repoB, lastAccessedAt: Date(timeIntervalSince1970: 100), sizeBytes: 50)
        ]

        let plan = MirrorCacheManager.cleanupPlan(
            entries: entries,
            quotaGB: 0,
            totalUsageBytes: 90,
            sizeAfterGC: { repoID in
                repoID == repoB ? 45 : 40
            }
        )

        #expect(plan.steps.prefix(2) == [.garbageCollect(repoID: repoB), .deleteMirror(repoID: repoB)])
        #expect(plan.steps.suffix(2) == [.garbageCollect(repoID: repoA), .deleteMirror(repoID: repoA)])
        #expect(plan.finalUsageBytes == 0)
    }

    @Test func cleanupPlanDoesNothingWhenUnderQuota() {
        let entries = [
            MirrorCacheEntry(repoID: repoA, lastAccessedAt: .distantPast, sizeBytes: 10)
        ]
        let plan = MirrorCacheManager.cleanupPlan(
            entries: entries,
            quotaGB: 50,
            totalUsageBytes: 10,
            sizeAfterGC: { _ in 0 }
        )
        #expect(plan.steps.isEmpty)
        #expect(plan.finalUsageBytes == 10)
    }

    @Test func lastAccessedPrefersSuccessfulSyncTimestamp() {
        var repo = RepoConfig(
            id: repoA,
            name: "demo",
            srcURL: "git@github.com:org/src.git",
            targets: [],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        repo.lastSuccessfulSyncedAt = Date(timeIntervalSince1970: 500)
        let fallback = Date(timeIntervalSince1970: 100)
        #expect(MirrorCacheManager.lastAccessedAt(for: repo, mirrorModificationDate: fallback) == Date(timeIntervalSince1970: 500))
    }
}

struct CachePreferencesTests {
    @Test func loadsUnlimitedWhenKeyMissing() {
        let suite = "gitrelay.tests.cache-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(CachePreferences.load(from: defaults).cacheQuotaGB == nil)
    }

    @Test func persistsAndReloadsQuota() {
        let suite = "gitrelay.tests.cache-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = CachePreferences(cacheQuotaGB: 50)
        prefs.save(to: defaults)
        #expect(CachePreferences.load(from: defaults).cacheQuotaGB == 50)

        CachePreferences.default.save(to: defaults)
        #expect(CachePreferences.load(from: defaults).cacheQuotaGB == nil)
    }
}

@MainActor
struct CachePreferencesStoreTests {
    @Test func resetToDefaultsClearsQuota() {
        let suite = "gitrelay.tests.cache-store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CachePreferencesStore(defaults: defaults)
        store.preferences = CachePreferences(cacheQuotaGB: 25)
        store.resetToDefaults()
        #expect(store.preferences.cacheQuotaGB == nil)
    }
}

@MainActor
struct MirrorCacheServiceTests {
    private let repoA = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private let repoB = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

    @Test func performCleanupRunsGCThenDeleteInLRUOrder() async {
        final class SizeBox {
            var values: [UUID: Int64]
            init(_ values: [UUID: Int64]) { self.values = values }
        }
        let sizes = SizeBox([
            repoA: 80,
            repoB: 80
        ])
        var gcCalls: [UUID] = []
        var deleteCalls: [UUID] = []

        let repos = [
            RepoConfig(
                id: repoA,
                name: "a",
                srcURL: "git@github.com:org/a.git",
                targets: [],
                createdAt: Date(timeIntervalSince1970: 0),
                lastSuccessfulSyncedAt: Date(timeIntervalSince1970: 200)
            ),
            RepoConfig(
                id: repoB,
                name: "b",
                srcURL: "git@github.com:org/b.git",
                targets: [],
                createdAt: Date(timeIntervalSince1970: 0),
                lastSuccessfulSyncedAt: Date(timeIntervalSince1970: 100)
            )
        ]

        let result = await MirrorCacheService.performCleanup(
            repos: repos,
            quotaGB: 0,
            sizeOf: { url in
                guard let id = UUID(uuidString: url.lastPathComponent) else { return 0 }
                return sizes.values[id] ?? 0
            },
            runGarbageCollection: { repoID in
                gcCalls.append(repoID)
            },
            deleteMirror: { repoID in
                deleteCalls.append(repoID)
                sizes.values[repoID] = 0
            }
        )

        #expect(gcCalls == [repoB, repoA])
        #expect(deleteCalls == [repoB, repoA])
        #expect(result.finalUsageBytes == 0)
        #expect(result.bytesFreed == 160)
    }

    @Test func performCleanupNoOpsWhenUnlimited() async {
        let repos = [
            RepoConfig(
                id: repoA,
                name: "a",
                srcURL: "git@github.com:org/a.git",
                targets: [],
                createdAt: Date(timeIntervalSince1970: 0)
            )
        ]

        let result = await MirrorCacheService.performCleanup(
            repos: repos,
            quotaGB: nil,
            sizeOf: { _ in 999_999 }
        )

        #expect(result.steps.isEmpty)
        #expect(result.finalUsageBytes == 999_999)
    }

    @Test func freeMirrorSpaceDeletesAfterGC() async {
        var deleted = false
        let freed = await MirrorCacheService.freeMirrorSpace(
            for: repoA,
            sizeOf: { _ in 128 },
            runGarbageCollection: { _ in },
            deleteMirror: { _ in deleted = true }
        )

        #expect(freed == 128)
        #expect(deleted)
    }
}

// MARK: - OrgRepoDiff

struct OrgRepoDiffTests {
    private func remote(_ fullName: String) -> RemoteRepo {
        RemoteRepo(
            id: fullName,
            name: fullName.split(separator: "/").last.map(String.init) ?? fullName,
            fullName: fullName,
            description: nil,
            isPrivate: false,
            httpsCloneURL: "https://github.com/\(fullName).git",
            sshCloneURL: "git@github.com:\(fullName).git",
            defaultBranch: "main"
        )
    }

    private func localRepo(srcURL: String) -> RepoConfig {
        RepoConfig(
            id: UUID(),
            name: "mirror",
            srcURL: srcURL,
            targets: [],
            createdAt: Date()
        )
    }

    @Test func newReposExcludesAlreadyMirroredPaths() {
        let remoteRepos = [
            remote("acme/alpha"),
            remote("acme/beta"),
            remote("acme/gamma")
        ]
        let local = [
            localRepo(srcURL: "git@github.com:acme/alpha.git"),
            localRepo(srcURL: "https://github.com/acme/beta.git")
        ]

        let result = OrgRepoDiff.newRepos(remoteRepos: remoteRepos, localRepos: local)
        #expect(result.map(\.fullName) == ["acme/gamma"])
    }

    @Test func syncedRemotePathsIsCaseInsensitive() {
        let local = [localRepo(srcURL: "git@github.com:Acme/Alpha.git")]
        let paths = OrgRepoDiff.syncedRemotePaths(from: local)
        #expect(paths.contains("acme/alpha"))
    }
}

// MARK: - OrgDiscoveryNotificationCopy

struct OrgDiscoveryNotificationCopyTests {
    @Test func singleRepoTitleUsesOrganizationName() {
        let title = OrgDiscoveryNotificationCopy.title(newRepoCount: 1, organizationName: "acme")
        #expect(title.contains("acme"))
    }

    @Test func pluralTitleIncludesCount() {
        let title = OrgDiscoveryNotificationCopy.title(newRepoCount: 3, organizationName: "acme")
        #expect(title.contains("3"))
        #expect(title.contains("acme"))
    }

    @Test func bodyListsPreviewNames() {
        let body = OrgDiscoveryNotificationCopy.body(
            newRepoCount: 2,
            previewNames: ["alpha", "beta"]
        )
        #expect(body.contains("alpha"))
        #expect(body.contains("beta"))
    }

    @Test func bodyUsesFallbackWhenNoPreview() {
        let body = OrgDiscoveryNotificationCopy.body(newRepoCount: 1, previewNames: [])
        #expect(body.contains("Tap to review"))
    }
}

// MARK: - OrgSubscriptionTemplateApplier

struct OrgSubscriptionTemplateApplierTests {
    private var sampleRepo: RemoteRepo {
        RemoteRepo(
            id: "acme/widget",
            name: "widget",
            fullName: "acme/widget",
            description: nil,
            isPrivate: false,
            httpsCloneURL: "https://github.com/acme/widget.git",
            sshCloneURL: "git@github.com:acme/widget.git",
            defaultBranch: "main"
        )
    }

    @Test func destinationURLSubstitutesNamePlaceholder() {
        var template = OrgSubscriptionTemplate.default
        template.targetURLTemplate = "git@backup.local:mirrors/{name}.git"
        let url = OrgSubscriptionTemplateApplier.destinationURL(for: sampleRepo, template: template)
        #expect(url == "git@backup.local:mirrors/widget.git")
    }

    @Test func makeConfigAppliesPrefixAndFrequency() {
        var template = OrgSubscriptionTemplate.default
        template.namePrefix = "mirror-"
        template.frequency = .hour1
        template.targetURLTemplate = "git@backup.local:mirrors/{name}.git"
        let config = OrgSubscriptionTemplateApplier.makeConfig(
            repo: sampleRepo,
            template: template,
            dstURL: "git@backup.local:mirrors/widget.git"
        )
        #expect(config.name == "mirror-widget")
        #expect(config.frequency == .hour1)
        #expect(config.srcURL == sampleRepo.sshCloneURL)
    }

    @Test func isValidTemplateRequiresNamePlaceholder() {
        var template = OrgSubscriptionTemplate.default
        template.targetURLTemplate = "git@backup.local:mirrors/repo.git"
        #expect(!OrgSubscriptionTemplateApplier.isValidTemplate(template))

        template.targetURLTemplate = "git@backup.local:mirrors/{name}.git"
        #expect(OrgSubscriptionTemplateApplier.isValidTemplate(template))
    }
}

// MARK: - OrgSubscriptionStore

@MainActor
struct OrgSubscriptionStoreTests {
    @Test func roundTripsPreferencesAndSubscriptions() {
        let suite = "gitrelay.tests.org-sub.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = OrgSubscriptionStore(defaults: defaults)
        store.preferences = OrgSubscriptionPreferences(pollFrequency: .week1, notificationsEnabled: false)
        let subscription = OrgSubscription(
            provider: .github,
            accountLabel: "work",
            organizationName: "acme"
        )
        store.add(subscription)

        let reloaded = OrgSubscriptionStore(defaults: defaults)
        #expect(reloaded.preferences.pollFrequency == .week1)
        #expect(reloaded.preferences.notificationsEnabled == false)
        #expect(reloaded.subscriptions.count == 1)
        #expect(reloaded.subscriptions[0].organizationName == "acme")
    }
}

// MARK: - OrgSubscriptionPoller

@MainActor
struct OrgSubscriptionPollerTests {
    @Test func checkSubscriptionDiffsAgainstLocalRepos() async {
        let suite = "gitrelay.tests.org-poller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = OrgSubscriptionStore(defaults: defaults)
        let subscription = OrgSubscription(
            provider: .github,
            organizationName: "acme"
        )
        store.add(subscription)

        let remoteRepos = [
            RemoteRepo(
                id: "acme/existing",
                name: "existing",
                fullName: "acme/existing",
                description: nil,
                isPrivate: false,
                httpsCloneURL: "https://github.com/acme/existing.git",
                sshCloneURL: "git@github.com:acme/existing.git",
                defaultBranch: "main"
            ),
            RemoteRepo(
                id: "acme/new-repo",
                name: "new-repo",
                fullName: "acme/new-repo",
                description: nil,
                isPrivate: false,
                httpsCloneURL: "https://github.com/acme/new-repo.git",
                sshCloneURL: "git@github.com:acme/new-repo.git",
                defaultBranch: "main"
            )
        ]

        let fetcher = OrgRemoteRepoFetcher { _, _, _, _, page, _ in
            RemoteRepoPage(repos: remoteRepos, hasMore: false, nextPage: page + 1)
        }
        let poller = OrgSubscriptionPoller(store: store, fetcher: fetcher)

        try? ProviderTokenStore.save(token: "test-token", provider: .github)

        let localRepos = [
            RepoConfig(
                id: UUID(),
                name: "existing",
                srcURL: "git@github.com:acme/existing.git",
                targets: [],
                createdAt: Date()
            )
        ]

        let result = await poller.checkSubscription(subscription, localRepos: localRepos)
        defer { ProviderTokenStore.delete(provider: .github) }

        #expect(result?.newRepos.map(\.fullName) == ["acme/new-repo"])
        #expect(result?.allRemoteRepos.count == 2)
        #expect(store.subscription(id: subscription.id)?.lastCheckedAt != nil)
    }
}


// MARK: - Git LFS mirroring

struct LFSAttributesDetectorTests {
    @Test func detectsFilterLFSInGitattributes() {
        let content = """
        *.psd filter=lfs diff=lfs merge=lfs -text
        # comment
        *.md text
        """
        #expect(LFSAttributesDetector.containsLFSFilter(content))
    }

    @Test func ignoresCommentsAndNonLFSAttributes() {
        let content = """
        # *.bin filter=lfs
        *.txt text
        """
        #expect(!LFSAttributesDetector.containsLFSFilter(content))
    }

    @Test func recognizesNestedGitAttributesPaths() {
        #expect(LFSAttributesDetector.isGitAttributesPath(".gitattributes"))
        #expect(LFSAttributesDetector.isGitAttributesPath("subdir/.gitattributes"))
        #expect(!LFSAttributesDetector.isGitAttributesPath("README.md"))
    }
}

struct LFSMirrorPlannerTests {
    @Test func offAlwaysSkips() {
        #expect(LFSMirrorPlanner.decide(mode: .off, usesLFS: true, gitLFSAvailable: true) == .skip)
        #expect(LFSMirrorPlanner.decide(mode: .off, usesLFS: true, gitLFSAvailable: false) == .skip)
    }

    @Test func autoSkipsWhenNoLFS() {
        #expect(LFSMirrorPlanner.decide(mode: .auto, usesLFS: false, gitLFSAvailable: true) == .skip)
    }

    @Test func autoWarnsWhenToolMissing() {
        #expect(LFSMirrorPlanner.decide(mode: .auto, usesLFS: true, gitLFSAvailable: false) == .warnMissingTool)
    }

    @Test func autoFetchesWhenPresent() {
        #expect(LFSMirrorPlanner.decide(mode: .auto, usesLFS: true, gitLFSAvailable: true) == .fetchThenPush)
    }
}

struct GitLFSArgumentsTests {
    @Test func fetchAndPushArgsMatchGitLFSCLI() {
        #expect(GitLFSArguments.fetchAllArgs == ["lfs", "fetch", "--all"])
        #expect(GitLFSArguments.pushAllArgs(remoteURL: "git@example.com:org/dst.git") == [
            "lfs", "push", "--all", "git@example.com:org/dst.git"
        ])
    }
}

struct GitLFSToolTests {
    @Test func candidatePathsPreferHomebrewAndUsrLocal() {
        let paths = GitLFSTool.candidatePaths(homeDirectory: "/Users/demo")
        #expect(paths.contains("/opt/homebrew/bin/git-lfs"))
        #expect(paths.contains("/usr/local/bin/git-lfs"))
        #expect(paths.contains("/Users/demo/.local/bin/git-lfs"))
    }

    @Test func isAvailableUsesInjectedFileExists() {
        #expect(GitLFSTool.isAvailable(fileExists: { $0.hasSuffix("/git-lfs") }, homeDirectory: "/tmp"))
        #expect(!GitLFSTool.isAvailable(fileExists: { _ in false }, homeDirectory: "/tmp"))
    }
}

actor FakeLFSCommandRunner: LFSCommandRunning {
    var available: Bool
    var usesLFS: Bool
    private(set) var fetchCount = 0
    private(set) var pushedURLs: [String] = []
    var fetchError: Error?
    var pushError: Error?

    init(available: Bool, usesLFS: Bool) {
        self.available = available
        self.usesLFS = usesLFS
    }

    func isGitLFSAvailable() async throws -> Bool { available }

    func repositoryUsesLFS(mirrorPath: String) async throws -> Bool { usesLFS }

    func lfsFetchAll(
        mirrorPath: String,
        env: [String: String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws {
        if let fetchError { throw fetchError }
        fetchCount += 1
    }

    func lfsPushAll(
        mirrorPath: String,
        remoteURL: String,
        env: [String: String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws {
        if let pushError { throw pushError }
        pushedURLs.append(remoteURL)
    }
}

struct LFSMirrorServiceTests {
    @Test func lfsPresentInvokesFetchAndPush() async throws {
        let runner = FakeLFSCommandRunner(available: true, usesLFS: true)
        let service = LFSMirrorService(runner: runner)
        var logs: [String] = []

        let prepare = try await service.prepareAfterSourceFetch(
            mode: .auto,
            mirrorPath: "/tmp/mirror",
            env: [:],
            log: { logs.append($0) }
        )
        #expect(prepare == .readyToPush)
        #expect(await runner.fetchCount == 1)

        try await service.pushToDestination(
            mirrorPath: "/tmp/mirror",
            remoteURL: "git@example.com:org/dst.git",
            env: [:],
            log: { logs.append($0) }
        )
        #expect(await runner.pushedURLs == ["git@example.com:org/dst.git"])
        #expect(logs.contains(where: { $0.contains("Fetching Git LFS") || $0.contains("LFS") }))
    }

    @Test func noLFSSkipsFetchAndPush() async throws {
        let runner = FakeLFSCommandRunner(available: true, usesLFS: false)
        let service = LFSMirrorService(runner: runner)
        var logs: [String] = []

        let prepare = try await service.prepareAfterSourceFetch(
            mode: .auto,
            mirrorPath: "/tmp/mirror",
            env: [:],
            log: { logs.append($0) }
        )
        #expect(prepare == .skipped)
        #expect(await runner.fetchCount == 0)
        #expect(await runner.pushedURLs.isEmpty)
    }

    @Test func missingGitLFSWarnsWithoutFailingPrepare() async throws {
        let runner = FakeLFSCommandRunner(available: false, usesLFS: true)
        let service = LFSMirrorService(runner: runner)
        var logs: [String] = []

        let prepare = try await service.prepareAfterSourceFetch(
            mode: .auto,
            mirrorPath: "/tmp/mirror",
            env: [:],
            log: { logs.append($0) }
        )
        #expect(prepare == .warnedMissingTool)
        #expect(await runner.fetchCount == 0)
        #expect(logs.contains(where: LFSMirrorMessages.isMissingGitLFSWarning))
        #expect(logs.contains(where: { $0.contains("brew install git-lfs") || $0.contains("git-lfs") }))
        // Missing tool is a soft warning: callers treat git sync as success.
        #expect(prepare != .readyToPush)
    }

    @Test func modeOffSkipsEvenWhenLFSPresent() async throws {
        let runner = FakeLFSCommandRunner(available: true, usesLFS: true)
        let service = LFSMirrorService(runner: runner)

        let prepare = try await service.prepareAfterSourceFetch(
            mode: .off,
            mirrorPath: "/tmp/mirror",
            env: [:],
            log: { _ in }
        )
        #expect(prepare == .skipped)
        #expect(await runner.fetchCount == 0)
    }
}

@MainActor
struct RepoConfigLFSMirrorModeTests {
    @Test func defaultsToAuto() {
        let repo = RepoConfig(
            name: "lfs-repo",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )
        #expect(repo.lfsMirrorMode == .auto)
    }

    @Test func legacyJSONWithoutLFSModeDecodesAsAuto() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000043",
          "name": "legacy-lfs",
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
        #expect(repo.lfsMirrorMode == .auto)
    }

    @Test func offModeRoundTripsAndOmitsDefaultAuto() throws {
        var repo = RepoConfig(
            name: "lfs-off",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git",
            lfsMirrorMode: .off
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(repo)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["lfsMirrorMode"] as? String == "off")

        repo.lfsMirrorMode = .auto
        let autoData = try encoder.encode(repo)
        let autoObject = try JSONSerialization.jsonObject(with: autoData) as? [String: Any]
        #expect(autoObject?["lfsMirrorMode"] == nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RepoConfig.self, from: data)
        #expect(decoded.lfsMirrorMode == .off)
    }
}

@MainActor
struct AddEditRepoLFSMirrorModeTests {
    @Test func buildRepoConfigPreservesLFSMode() {
        let vm = AddEditRepoViewModel()
        vm.name = "demo"
        vm.srcURL = "git@github.com:org/src.git"
        vm.targets[0].url = "git@github.com:org/dst.git"
        vm.lfsMirrorMode = .off
        #expect(vm.validate())
        #expect(vm.buildRepoConfig().lfsMirrorMode == .off)
    }
}

// MARK: - Transient git retry (#44)

struct GitTransientErrorClassifierTests {
    @Test func classifiesNetworkTimeoutsAsRetryable() {
        let errors: [Error] = [
            GitError.processError(128, "fatal: unable to access 'https://github.com/x/y.git/': Could not resolve host: github.com"),
            GitError.processError(128, "ssh: connect to host github.com port 22: Connection timed out"),
            GitError.processError(128, "Recv failure: Connection reset by peer"),
            GitError.processError(128, "The requested URL returned error: 502"),
            GitError.processError(128, "RPC failed; HTTP 503 curl 22"),
            GitError.processError(128, "fatal: Network is unreachable"),
        ]
        for error in errors {
            guard case .retryable = GitTransientErrorClassifier.classify(error) else {
                Issue.record("expected retryable for \(error.localizedDescription)")
                continue
            }
        }
    }

    @Test func classifiesAuthPermissionCorruptionAndCancelAsNonRetryable() {
        #expect(GitTransientErrorClassifier.classify(GitError.cancelled) == .cancelled)
        #expect(GitTransientErrorClassifier.classify(CancellationError()) == .cancelled)

        let nonRetryable: [Error] = [
            GitError.processError(128, "Authentication failed for 'https://github.com/x/y.git/'"),
            GitError.processError(128, "Permission denied (publickey)."),
            GitError.processError(128, "fatal: could not read Username for 'https://github.com': terminal prompts disabled"),
            GitError.processError(128, "error: corrupt loose object"),
            GitError.processError(128, "error: packfile is corrupt"),
            DestructivePushError.blocked(
                DestructivePushPlan(deletedRefs: ["refs/heads/old"], forcedUpdateRefs: [])
            ),
            SyncEngineError.noEnabledTargets,
        ]
        for error in nonRetryable {
            #expect(GitTransientErrorClassifier.classify(error) == .nonRetryable)
        }
    }

    @Test func redactsCredentialsBeforeClassifyingReason() {
        let error = GitError.processError(
            128,
            "fatal: unable to access 'https://secret-token@github.com/x/y.git/': Could not resolve host: github.com"
        )
        guard case .retryable(let reason) = GitTransientErrorClassifier.classify(error) else {
            Issue.record("expected retryable")
            return
        }
        #expect(!reason.contains("secret-token"))
        #expect(reason == "Could not resolve host")
    }
}

struct GitRetryPolicyTests {
    @Test func defaultScheduleIsTwoThenEightSeconds() {
        let policy = GitRetryPolicy.default
        #expect(policy.maxAttempts == 3)
        #expect(policy.delayAfterAttempt(1) == 2)
        #expect(policy.delayAfterAttempt(2) == 8)
        #expect(policy.delayAfterAttempt(3) == nil)
        #expect(GitRetryPolicy.delaySchedule(maxAttempts: 3) == [2, 8])
        #expect(GitRetryPolicy.delaySchedule(maxAttempts: 4) == [2, 8, 32])
    }

    @Test func clampsAttemptsSoTotalWaitStaysWithinThreeMinutes() {
        let policy = GitRetryPolicy(maxAttempts: 100)
        let schedule = GitRetryPolicy.delaySchedule(maxAttempts: policy.maxAttempts)
        #expect(schedule.reduce(0, +) <= GitRetryPolicy.maxTotalWaitSeconds)
        #expect(policy.maxAttempts == schedule.count + 1)
        #expect(policy.maxAttempts < 100)
    }

    @Test func singleAttemptMeansNoRetries() {
        let policy = GitRetryPolicy(maxAttempts: 1)
        #expect(policy.maxAttempts == 1)
        #expect(policy.delayAfterAttempt(1) == nil)
        #expect(GitRetryPolicy.delaySchedule(maxAttempts: 1).isEmpty)
    }
}

private final class RetryTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}

private final class RetryTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

private final class RetryTestSleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [TimeInterval] = []
    var values: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    func append(_ value: TimeInterval) {
        lock.lock()
        _values.append(value)
        lock.unlock()
    }
}

private final class RetryTestStringLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    func append(_ value: String) {
        lock.lock()
        _values.append(value)
        lock.unlock()
    }
}

@MainActor
struct GitRetryExecutorTests {
    @Test func transientErrorThenSuccessDoesNotSurfaceFailure() async throws {
        let attempts = RetryTestCounter()
        let sleeps = RetryTestSleepLog()
        let retries = RetryTestStringLog()

        let result = try await GitRetryExecutor.run(
            policy: .default,
            sleep: { delay in sleeps.append(delay) },
            onRetry: { next, max, reason in
                retries.append(GitRetryLog.line(attempt: next, maxAttempts: max, reason: reason))
            },
            operation: {
                let n = attempts.increment()
                if n == 1 {
                    throw GitError.processError(128, "ssh: connect to host github.com port 22: Connection timed out")
                }
                return "ok"
            }
        )

        #expect(result == "ok")
        #expect(attempts.value == 2)
        #expect(sleeps.values == [2])
        #expect(retries.values.count == 1)
        #expect(retries.values[0].contains("2"))
        #expect(retries.values[0].contains("3"))
        #expect(retries.values[0].lowercased().contains("timed out") || retries.values[0].contains("timeout") || retries.values[0].contains("Connection"))

        // A later successful retry must look like a normal success for failure counting.
        var repo = RepoConfig(
            name: "retry-ok",
            srcURL: "git@github.com:user/repo.git",
            dstURL: "git@github.com:user/mirror.git"
        )
        repo.recordSyncResult(error: nil)
        #expect(repo.consecutiveFailureCount == 0)
        #expect(repo.lastSyncError == nil)
    }

    @Test func nonRetryableErrorFailsImmediatelyWithoutSleep() async {
        let attempts = RetryTestCounter()
        let sleeps = RetryTestSleepLog()

        do {
            _ = try await GitRetryExecutor.run(
                policy: .default,
                sleep: { delay in sleeps.append(delay) },
                operation: {
                    _ = attempts.increment()
                    throw GitError.processError(128, "Authentication failed for 'https://github.com/x/y.git/'")
                }
            )
            Issue.record("expected authentication failure")
        } catch let error as GitError {
            guard case .processError = error else {
                Issue.record("expected processError")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }

        #expect(attempts.value == 1)
        #expect(sleeps.values.isEmpty)
    }

    @Test func cancellationAbortsBackoffWithoutWaitingRemainingDelay() async {
        let attempts = RetryTestCounter()
        let sleeps = RetryTestSleepLog()
        let cancelled = RetryTestFlag()

        do {
            _ = try await GitRetryExecutor.run(
                policy: .default,
                isCancelled: { cancelled.value },
                sleep: { delay in
                    sleeps.append(delay)
                    cancelled.value = true
                },
                operation: {
                    _ = attempts.increment()
                    throw GitError.processError(128, "Could not resolve host: github.com")
                }
            )
            Issue.record("expected cancellation")
        } catch let error as GitError {
            guard case .cancelled = error else {
                Issue.record("expected GitError.cancelled, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }

        #expect(attempts.value == 1)
        #expect(sleeps.values == [2])
        // Must not proceed to the 8s / 32s backoff slots after cancel.
        #expect(!sleeps.values.contains(8))
        #expect(!sleeps.values.contains(32))
    }

    @Test func retryLogRedactsCredentialURLs() {
        let line = GitRetryLog.line(
            attempt: 2,
            maxAttempts: 3,
            reason: "Could not resolve host in https://mytoken@github.com/x/y.git"
        )
        #expect(!line.contains("mytoken"))
        #expect(line.contains("****") || !line.contains("@github.com") || line.contains("https://****@"))
    }
}


// MARK: - Config export / import (#45)

struct ConfigExportImportTests {
    @Test func exportJSONOmitsTokenLikeFieldsAndValues() throws {
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!
        let secretTag = "super-secret-token-value"
        let repo = RepoConfig(
            id: repoID,
            name: "api",
            srcURL: "https://github.com/acme/api.git",
            targets: [
                MirrorTarget(
                    id: targetID,
                    url: "https://gitlab.com/acme/api.git",
                    auth: .httpsToken(keychainTag: secretTag)
                )
            ],
            srcAuth: .httpsToken(keychainTag: "\(repoID.uuidString)-src"),
            frequency: .min15,
            tags: ["prod"],
            mirrorReleases: true,
            lfsMirrorMode: .off,
            depth: 1,
            webhookEnabled: true
        )

        let document = ConfigExportCodec.makeDocument(
            repos: [repo],
            providerAccounts: [
                ExportedProviderAccount(provider: .github, label: "work", host: nil)
            ],
            orgSubscriptions: [
                OrgSubscription(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000cc")!,
                    provider: .github,
                    accountLabel: "work",
                    organizationName: "acme"
                )
            ],
            orgSubscriptionPreferences: .default,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try ConfigExportCodec.encode(document)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(document.schemaVersion == ConfigExportDocument.currentSchemaVersion)
        #expect(!ConfigExportCodec.containsForbiddenSecretFields(json))
        #expect(!json.contains(secretTag))
        #expect(!json.contains("keychainTag"))
        #expect(!json.localizedCaseInsensitiveContains("-----BEGIN"))
        #expect(json.contains("\"kind\" : \"httpsToken\"") || json.contains("\"kind\":\"httpsToken\""))
        #expect(json.contains("\"schemaVersion\""))
        #expect(json.contains("work"))
        #expect(json.contains("acme"))
    }

    @Test func exportOmitsMachineLocalSSHKeyPaths() throws {
        let repo = RepoConfig(
            name: "keys",
            srcURL: "git@github.com:acme/keys.git",
            dstURL: "git@gitlab.com:acme/keys.git",
            srcAuth: .sshKey(privateKeyPath: "/Users/me/.ssh/id_ed25519"),
            dstAuth: .sshKey(privateKeyPath: "relative/id_ed25519")
        )
        let document = ConfigExportCodec.makeDocument(
            repos: [repo],
            providerAccounts: [],
            orgSubscriptions: [],
            orgSubscriptionPreferences: nil
        )
        let data = try ConfigExportCodec.encode(document)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("/Users/me/.ssh/id_ed25519"))
        #expect(!json.contains("\\/Users\\/me\\/.ssh\\/id_ed25519"))
        // JSONEncoder may escape `/` as `\/`.
        #expect(json.contains("relative/id_ed25519") || json.contains("relative\\/id_ed25519"))
    }

    @Test func importReplaceRestoresRepoCount() throws {
        let existing = [
            RepoConfig(name: "old", srcURL: "a", dstURL: "b")
        ]
        let importedIDs = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        ]
        let document = ConfigExportDocument(
            repos: importedIDs.map {
                ExportedRepo(from: RepoConfig(
                    id: $0,
                    name: "r-\($0.uuidString.prefix(4))",
                    srcURL: "git@github.com:acme/r.git",
                    dstURL: "git@gitlab.com:acme/r.git",
                    frequency: .hour1
                ))
            },
            providerAccounts: [],
            orgSubscriptions: []
        )

        let plan = ConfigExportCodec.planImport(
            document: document,
            mode: .replace,
            existingRepos: existing,
            probe: .alwaysPresent
        )
        #expect(plan.repos.count == 3)
        #expect(plan.importedRepoCount == 3)
        #expect(plan.skippedRepoCount == 0)
    }

    @Test func importMergeSkipsSameIDByDefault() {
        let sharedID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let existing = [
            RepoConfig(id: sharedID, name: "keep-me", srcURL: "a", dstURL: "b")
        ]
        let document = ConfigExportDocument(
            repos: [
                ExportedRepo(from: RepoConfig(
                    id: sharedID,
                    name: "incoming",
                    srcURL: "c",
                    dstURL: "d"
                )),
                ExportedRepo(from: RepoConfig(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
                    name: "new-one",
                    srcURL: "e",
                    dstURL: "f"
                ))
            ]
        )

        let plan = ConfigExportCodec.planImport(
            document: document,
            mode: .merge,
            existingRepos: existing,
            probe: .alwaysPresent
        )
        #expect(plan.repos.count == 2)
        #expect(plan.importedRepoCount == 1)
        #expect(plan.skippedRepoCount == 1)
        #expect(plan.repos.first?.name == "keep-me")
    }

    @Test func httpsTokenWithoutKeychainIsMarkedNeedsCredentials() {
        let repoID = UUID(uuidString: "00000000-0000-0000-0000-0000000000dd")!
        let exported = ExportedRepo(from: RepoConfig(
            id: repoID,
            name: "needs-auth",
            srcURL: "https://github.com/acme/x.git",
            dstURL: "https://gitlab.com/acme/x.git",
            srcAuth: .httpsToken(keychainTag: "\(repoID.uuidString)-src"),
            frequency: .min15
        ))
        let imported = exported.toRepoConfig(probe: .alwaysMissing)
        #expect(imported.needsCredentials)
        #expect(RepoCredentialGate.needsCredentials(for: imported, probe: .alwaysMissing))
    }

    @MainActor
    @Test func schedulerSkipsReposNeedingCredentials() {
        let scheduler = SyncScheduler()
        defer { scheduler.invalidateAll() }

        var repo = RepoConfig(
            name: "paused",
            srcURL: "git@github.com:acme/p.git",
            dstURL: "git@gitlab.com:acme/p.git",
            frequency: .min15
        )
        repo.needsCredentials = true
        scheduler.schedule(repo: repo)
        #expect(scheduler.nextFireDate(for: repo.id) == nil)

        repo.needsCredentials = false
        scheduler.schedule(repo: repo)
        #expect(scheduler.nextFireDate(for: repo.id) != nil)
    }

    @Test func corruptJSONThrowsAndDoesNotProduceDocument() {
        let garbage = Data("{not-json".utf8)
        #expect(throws: ConfigExportError.corruptJSON) {
            try ConfigExportCodec.decode(garbage)
        }
    }

    @Test func unsupportedSchemaVersionThrows() throws {
        let payload = """
        {
          "schemaVersion": 99,
          "repos": [],
          "providerAccounts": [],
          "orgSubscriptions": []
        }
        """
        do {
            _ = try ConfigExportCodec.decode(Data(payload.utf8))
            Issue.record("expected unsupported schema version error")
        } catch let error as ConfigExportError {
            guard case .unsupportedSchemaVersion(let found, let supported) = error else {
                Issue.record("wrong error \(error)")
                return
            }
            #expect(found == 99)
            #expect(supported == ConfigExportDocument.currentSchemaVersion)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func partialDecodeDoesNotHalfApply() throws {
        let payload = """
        {
          "schemaVersion": 1,
          "repos": [
            {
              "id": "not-a-uuid",
              "name": "broken",
              "srcURL": "x",
              "targets": [],
              "srcAuth": { "kind": "sshAgent" },
              "frequency": "手动",
              "destructivePushPolicy": "strict",
              "defaultBranch": "main",
              "createdAt": "2026-04-25T12:00:00Z",
              "tags": [],
              "mirrorReleases": false,
              "lfsMirrorMode": "auto",
              "refSpecs": [],
              "webhookEnabled": false
            }
          ],
          "providerAccounts": [],
          "orgSubscriptions": []
        }
        """
        var store = [
            RepoConfig(name: "untouched", srcURL: "a", dstURL: "b")
        ]
        let snapshot = store

        do {
            let document = try ConfigExportCodec.decode(Data(payload.utf8))
            store = ConfigExportCodec.planImport(
                document: document,
                mode: .replace,
                existingRepos: store,
                probe: .alwaysPresent
            ).repos
            Issue.record("decode should have failed")
        } catch is ConfigExportError {
            #expect(store == snapshot)
        } catch {
            #expect(store == snapshot)
        }
    }

    @MainActor
    @Test func importFailureLeavesRepoStoreUnchanged() throws {
        let suite = "config-import-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-config-import-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            Constants.setBaseDirectoryForTesting(nil)
            try? FileManager.default.removeItem(at: tempDir)
        }
        Constants.setBaseDirectoryForTesting(tempDir)

        let orgStore = OrgSubscriptionStore(defaults: defaults)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            orgSubscriptionStore: orgStore,
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            securityPreferencesStore: SecurityPreferencesStore(defaults: defaults),
            cachePreferencesStore: CachePreferencesStore(defaults: defaults),
            biometricAuthenticator: PermissiveBiometricAuthenticator()
        )

        let original = RepoConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000ee")!,
            name: "keep",
            srcURL: "git@github.com:acme/keep.git",
            dstURL: "git@gitlab.com:acme/keep.git"
        )
        vm.repos = [original]
        let beforeCount = vm.repos.count

        #expect(throws: ConfigExportError.self) {
            try vm.importConfiguration(from: Data("totally-broken".utf8), mode: .replace)
        }
        #expect(vm.repos.count == beforeCount)
        #expect(vm.repos.first?.name == "keep")
    }

    @MainActor
    @Test func successfulImportMarksMissingHTTPSCredentials() throws {
        let suite = "config-import-ok-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-config-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            Constants.setBaseDirectoryForTesting(nil)
            try? FileManager.default.removeItem(at: tempDir)
        }
        Constants.setBaseDirectoryForTesting(tempDir)

        let orgStore = OrgSubscriptionStore(defaults: defaults)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            orgSubscriptionStore: orgStore,
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            securityPreferencesStore: SecurityPreferencesStore(defaults: defaults),
            cachePreferencesStore: CachePreferencesStore(defaults: defaults),
            biometricAuthenticator: PermissiveBiometricAuthenticator()
        )
        vm.repos = []

        let repoID = UUID(uuidString: "00000000-0000-0000-0000-0000000000ff")!
        let document = ConfigExportDocument(
            repos: [
                ExportedRepo(from: RepoConfig(
                    id: repoID,
                    name: "imported",
                    srcURL: "https://github.com/acme/imported.git",
                    dstURL: "https://gitlab.com/acme/imported.git",
                    srcAuth: .httpsToken(keychainTag: "\(repoID.uuidString)-src"),
                    frequency: .min15
                ))
            ],
            providerAccounts: [
                ExportedProviderAccount(provider: .github, label: "default", host: nil)
            ]
        )
        let data = try ConfigExportCodec.encode(document)
        let plan = try vm.importConfiguration(from: data, mode: .replace, probe: .alwaysMissing)

        #expect(plan.importedRepoCount == 1)
        #expect(vm.repos.count == 1)
        #expect(vm.repos[0].needsCredentials)
        #expect(vm.nextFireDate(for: repoID) == nil)

        vm.triggerSync(repoID: repoID)
        #expect(vm.errorMessage == RepoCredentialGate.missingCredentialsMessage)
        if case .failed(let message) = vm.statuses[repoID] {
            #expect(message == RepoCredentialGate.missingCredentialsMessage)
        } else {
            Issue.record("expected failed status for missing credentials")
        }
    }
}

// MARK: - SyncConcurrencyGate

@MainActor
struct SyncConcurrencyGateTests {
    @Test func defaultCapIsTwoAndClampsRange() {
        #expect(SyncConcurrencyGate.defaultMaxConcurrent == 2)
        #expect(SyncConcurrencyGate.clamped(0) == 1)
        #expect(SyncConcurrencyGate.clamped(1) == 1)
        #expect(SyncConcurrencyGate.clamped(4) == 4)
        #expect(SyncConcurrencyGate.clamped(99) == 4)
    }

    @Test func thirdRequestIsQueuedUnderDefaultCap() {
        let gate = SyncConcurrencyGate()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        #expect(gate.request(a) == .beginImmediately)
        #expect(gate.request(b) == .beginImmediately)
        #expect(gate.request(c) == .enqueued)
        #expect(gate.queuedRepoIDs == [c])
        #expect(gate.activeCount == 2)
    }

    @Test func capOneNeverRunsTwoConcurrently() {
        let gate = SyncConcurrencyGate(maxConcurrent: 1)
        let a = UUID()
        let b = UUID()

        #expect(gate.request(a) == .beginImmediately)
        #expect(gate.request(b) == .enqueued)
        #expect(gate.activeCount == 1)
        #expect(gate.finishActive(a) == b)
        #expect(gate.activeCount == 1)
        #expect(gate.queuedCount == 0)
    }

    @Test func cancelQueuedDoesNotAdmitOrActivate() {
        let gate = SyncConcurrencyGate(maxConcurrent: 1)
        let a = UUID()
        let b = UUID()

        #expect(gate.request(a) == .beginImmediately)
        #expect(gate.request(b) == .enqueued)
        #expect(gate.cancelQueued(b))
        #expect(gate.queuedCount == 0)
        #expect(gate.finishActive(a) == nil)
        #expect(gate.activeCount == 0)
    }

    @Test func raisingCapAdmitsQueuedFIFO() {
        let gate = SyncConcurrencyGate(maxConcurrent: 1)
        let a = UUID()
        let b = UUID()
        let c = UUID()
        #expect(gate.request(a) == .beginImmediately)
        #expect(gate.request(b) == .enqueued)
        #expect(gate.request(c) == .enqueued)

        let admitted = gate.updateMaxConcurrent(3)
        #expect(admitted == [b, c])
        #expect(gate.queuedCount == 0)
        #expect(gate.activeCount == 3)
    }

    @Test func resetDropsQueueWithoutDraining() {
        let gate = SyncConcurrencyGate(maxConcurrent: 1)
        let a = UUID()
        let b = UUID()
        #expect(gate.request(a) == .beginImmediately)
        #expect(gate.request(b) == .enqueued)
        gate.reset()
        #expect(gate.activeCount == 0)
        #expect(gate.queuedCount == 0)
    }
}

// MARK: - Sync concurrency (AppViewModel)

@MainActor
struct SyncConcurrencyAppViewModelTests {
    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-sync-concurrency-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            notificationPreferencesStore: NotificationPreferencesStore(defaults: defaults)
        )
        vm.suspendSyncEngineForTesting = true
        return vm
    }

    private func addSSHRepo(to vm: AppViewModel, name: String) -> UUID {
        let id = UUID()
        vm.addRepo(
            RepoConfig(
                id: id,
                name: name,
                srcURL: "git@github.com:user/\(name).git",
                dstURL: "git@github.com:user/\(name)-mirror.git",
                frequency: .manual
            )
        )
        return id
    }

    @Test func thirdTriggerWaitsUnderDefaultCapOfTwo() {
        let suite = "gitrelay.tests.sync-concurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        let first = addSSHRepo(to: vm, name: "one")
        let second = addSSHRepo(to: vm, name: "two")
        let third = addSSHRepo(to: vm, name: "three")

        vm.triggerSync(repoID: first)
        vm.triggerSync(repoID: second)
        vm.triggerSync(repoID: third)

        #expect(vm.inProgressSyncIDs == Set([first, second]))
        #expect(vm.statuses[third] == .queued)
        #expect(!vm.inProgressSyncIDs.contains(third))
    }

    @Test func capOneIsNotConcurrent() {
        let suite = "gitrelay.tests.sync-concurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        var prefs = vm.notificationPreferences.preferences
        prefs.maxConcurrentSyncs = 1
        vm.notificationPreferences.preferences = prefs

        let first = addSSHRepo(to: vm, name: "alpha")
        let second = addSSHRepo(to: vm, name: "beta")

        vm.triggerSync(repoID: first)
        vm.triggerSync(repoID: second)

        #expect(vm.inProgressSyncIDs == Set([first]))
        #expect(vm.statuses[first] == .syncing)
        #expect(vm.statuses[second] == .queued)
        #expect(!vm.inProgressSyncIDs.contains(second))
    }

    @Test func cancelQueuedDoesNotStartGit() {
        let suite = "gitrelay.tests.sync-concurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        var prefs = vm.notificationPreferences.preferences
        prefs.maxConcurrentSyncs = 1
        vm.notificationPreferences.preferences = prefs

        let first = addSSHRepo(to: vm, name: "running")
        let second = addSSHRepo(to: vm, name: "waiting")

        vm.triggerSync(repoID: first)
        vm.triggerSync(repoID: second)
        #expect(vm.statuses[second] == .queued)

        vm.cancelSync(repoID: second)
        #expect(vm.statuses[second] != .queued)
        #expect(!vm.inProgressSyncIDs.contains(second))

        // Finishing the active sync must not promote the cancelled repo.
        vm.cancelSync(repoID: first)
        #expect(!vm.inProgressSyncIDs.contains(second))
        #expect(vm.statuses[second] != .syncing)
        #expect(vm.statuses[second] != .queued)
    }

    @Test func finishingActivePromotesQueued() {
        let suite = "gitrelay.tests.sync-concurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        var prefs = vm.notificationPreferences.preferences
        prefs.maxConcurrentSyncs = 1
        vm.notificationPreferences.preferences = prefs

        let first = addSSHRepo(to: vm, name: "first")
        let second = addSSHRepo(to: vm, name: "second")

        vm.triggerSync(repoID: first)
        vm.triggerSync(repoID: second)
        #expect(vm.statuses[second] == .queued)

        vm.cancelSync(repoID: first)
        #expect(vm.inProgressSyncIDs == Set([second]))
        #expect(vm.statuses[second] == .syncing)
    }

    @Test func syncAllSharesTheSameCap() {
        let suite = "gitrelay.tests.sync-concurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        var prefs = vm.notificationPreferences.preferences
        prefs.maxConcurrentSyncs = 2
        vm.notificationPreferences.preferences = prefs

        let ids = (1...4).map { addSSHRepo(to: vm, name: "batch-\($0)") }
        vm.triggerSyncAll()

        #expect(vm.inProgressSyncIDs.count == 2)
        let queued = ids.filter { vm.statuses[$0] == .queued }
        #expect(queued.count == 2)
    }
}

// MARK: - Main window keyboard shortcuts (issue #69)

struct MainWindowShortcutBindingTests {
    @Test func bindingsUseCommandNFR() {
        #expect(MainWindowShortcutBinding.addRepository.keyCharacter == "n")
        #expect(MainWindowShortcutBinding.focusSearch.keyCharacter == "f")
        #expect(MainWindowShortcutBinding.syncSelected.keyCharacter == "r")
        #expect(MainWindowShortcutBinding.allCases.count == 3)
        for binding in MainWindowShortcutBinding.allCases {
            #expect(binding.isCommandOnly)
        }
    }

    @Test func menuTitlesMatchLocalizedCatalogKeys() {
        #expect(MainWindowShortcutBinding.addRepository.menuTitle == String(localized: "Add Repository"))
        #expect(MainWindowShortcutBinding.focusSearch.menuTitle == String(localized: "Search Repositories"))
        #expect(MainWindowShortcutBinding.syncSelected.menuTitle == String(localized: "Sync Selected Repository"))
    }
}

@MainActor
struct MainWindowShortcutCommandTests {
    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-main-shortcuts-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            notificationPreferencesStore: NotificationPreferencesStore(defaults: defaults)
        )
        vm.suspendSyncEngineForTesting = true
        return vm
    }

    private func addSSHRepo(to vm: AppViewModel, name: String) -> UUID {
        let id = UUID()
        vm.addRepo(
            RepoConfig(
                id: id,
                name: name,
                srcURL: "git@github.com:user/\(name).git",
                dstURL: "git@github.com:user/\(name)-mirror.git",
                frequency: .manual
            )
        )
        return id
    }

    @Test func openAddAndFocusSearchSetConsumablePendingFlags() {
        let suite = "gitrelay.tests.main-shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        #expect(!vm.consumePendingOpenAddRepository())
        #expect(!vm.consumePendingFocusSidebarSearch())

        vm.requestOpenAddRepository()
        #expect(vm.pendingOpenAddRepository)
        #expect(vm.consumePendingOpenAddRepository())
        #expect(!vm.pendingOpenAddRepository)
        #expect(!vm.consumePendingOpenAddRepository())

        vm.requestFocusSidebarSearch()
        #expect(vm.pendingFocusSidebarSearch)
        #expect(vm.consumePendingFocusSidebarSearch())
        #expect(!vm.pendingFocusSidebarSearch)
        #expect(!vm.consumePendingFocusSidebarSearch())
    }

    @Test func syncSelectedIsNoOpWithoutSelectionOrWhenAlreadySyncing() {
        let suite = "gitrelay.tests.main-shortcuts-sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        vm.syncMainWindowSelectedRepository()
        #expect(vm.inProgressSyncIDs.isEmpty)

        let repoID = addSSHRepo(to: vm, name: "selected")
        vm.mainWindowSelectedRepoID = repoID
        vm.syncMainWindowSelectedRepository()
        #expect(vm.inProgressSyncIDs == Set([repoID]))
        #expect(vm.statuses[repoID] == .syncing)

        vm.syncMainWindowSelectedRepository()
        #expect(vm.inProgressSyncIDs == Set([repoID]))
    }
}

// MARK: - String Catalog (issue #65)

struct StringCatalogLocaleTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func recentUIKeysExistInAppCatalogWithBothLocales() throws {
        let url = Self.repoRoot.appendingPathComponent("gitrelay/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])

        let required = [
            "Queued",
            "Sync Concurrency",
            "Max concurrent syncs: %lld",
            "Open at Login",
            "Keep in Menu Bar when closing main window",
            "Startup & Menu Bar",
            "Security",
            "Notifications",
            "Schedule",
            "Webhook",
            "Cache",
            "Configuration",
            "More Options",
            "Add and Start Syncing",
            "Re-enter credentials",
            "Open Log",
            "Personal Access Token",
            "Provider",
            "Gitea Host",
            "Gitea API Token",
            "Cloning...",
            "Fetching...",
            "Fetching LFS...",
            "Pushing...",
            "Pushing LFS...",
            "%lld / %lld objects",
            "Add Repository",
            "Search Repositories",
            "Sync Selected Repository",
            "Repository",
        ]

        for key in required {
            let entry = try #require(strings[key] as? [String: Any], "missing key \(key)")
            let locs = try #require(entry["localizations"] as? [String: Any])
            for locale in ["en", "zh-Hans"] {
                let unit = try #require(
                    (locs[locale] as? [String: Any])?["stringUnit"] as? [String: Any],
                    "\(key) missing \(locale)"
                )
                let value = try #require(unit["value"] as? String)
                #expect(!value.isEmpty, "\(key) \(locale) empty")
            }
        }
    }

    @Test func queuedExistsInWidgetCatalogWithBothLocales() throws {
        let url = Self.repoRoot.appendingPathComponent("gitrelayWidget/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        let entry = try #require(strings["Queued"] as? [String: Any])
        let locs = try #require(entry["localizations"] as? [String: Any])
        for locale in ["en", "zh-Hans"] {
            let unit = try #require(
                (locs[locale] as? [String: Any])?["stringUnit"] as? [String: Any]
            )
            let value = try #require(unit["value"] as? String)
            #expect(!value.isEmpty)
        }
    }
}

// MARK: - Sync phase progress (issue #67)

struct SyncPhaseTests {
    @Test func statusTitlesDistinguishCloneFetchLFSPush() {
        #expect(SyncPhase(.cloningSource).statusTitle == String(localized: "Cloning..."))
        #expect(SyncPhase(.fetchingSource).statusTitle == String(localized: "Fetching..."))
        #expect(SyncPhase(.fetchingLFS).statusTitle == String(localized: "Fetching LFS..."))
        #expect(SyncPhase(.pushingTarget("git@ex.com:a.git")).statusTitle == String(localized: "Pushing..."))
        #expect(SyncPhase(.pushingLFS("git@ex.com:a.git")).statusTitle == String(localized: "Pushing LFS..."))
        #expect(SyncPhase(.archivingTarget("/tmp/out")).statusTitle == String(localized: "Archiving..."))
    }

    @Test func displayCaptionIncludesParsedProgressWhenPresent() {
        let phase = SyncPhase(.fetchingSource, progressDetail: "1,234 / 2,000 objects")
        #expect(phase.displayCaption == "\(String(localized: "Fetching...")) · 1,234 / 2,000 objects")
        #expect(SyncPhase(.pushingTarget("dst")).displayCaption == String(localized: "Pushing..."))
    }
}

struct GitProgressParserTests {
    @Test func parsesReceivingObjectsCounts() {
        let detail = GitProgressParser.detail(
            from: "Receiving objects:  45% (1234/2745), 1.23 MiB | 500.00 KiB/s"
        )
        #expect(detail == String(localized: "\(1234) / \(2745) objects"))
    }

    @Test func parsesWritingObjectsCounts() {
        let detail = GitProgressParser.detail(
            from: "Writing objects: 100% (100/100), 12.34 KiB | 1.23 MiB/s, done."
        )
        #expect(detail == String(localized: "\(100) / \(100) objects"))
    }

    @Test func parsesLFSDownloadCounts() {
        let detail = GitProgressParser.detail(
            from: "Downloading LFS objects:  50% (5/10), 150 MB"
        )
        #expect(detail == String(localized: "\(5) / \(10) objects"))
    }

    @Test func fallsBackToBytesWhenCountsAbsent() {
        let detail = GitProgressParser.detail(
            from: "Receiving objects:  10% , 12.50 MiB | 2.00 MiB/s"
        )
        #expect(detail == "12.50 MiB")
    }

    @Test func ignoresNonProgressLines() {
        #expect(GitProgressParser.detail(from: "Fetching from source...") == nil)
        #expect(GitProgressParser.detail(from: "") == nil)
    }

    @Test func neverReturnsCredentialBearingRawLine() {
        let line = "https://ghp_secretTOKEN@github.com/org/repo.git"
        #expect(GitProgressParser.detail(from: line) == nil)
        let redacted = SyncEngine.redactCredentials(
            "Receiving objects:  1% (1/2) from https://ghp_secretTOKEN@github.com/org/repo.git"
        )
        #expect(redacted.contains("****@"))
        #expect(!redacted.contains("ghp_secretTOKEN"))
        let detail = GitProgressParser.detail(from: redacted)
        #expect(detail == String(localized: "\(1) / \(2) objects"))
        #expect(detail?.contains("ghp_secretTOKEN") != true)
        #expect(detail?.contains("https://") != true)
    }
}

@MainActor
struct SyncPhaseLifecycleTests {
    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-sync-phase-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            notificationPreferencesStore: NotificationPreferencesStore(defaults: defaults)
        )
        vm.suspendSyncEngineForTesting = true
        return vm
    }

    private func addSSHRepo(to vm: AppViewModel, name: String) -> UUID {
        let id = UUID()
        vm.addRepo(
            RepoConfig(
                id: id,
                name: name,
                srcURL: "git@github.com:user/\(name).git",
                dstURL: "git@github.com:user/\(name)-mirror.git",
                frequency: .manual
            )
        )
        return id
    }

    @Test func admittedSyncSetsPhaseAndClearsWhenDone() {
        let suite = "gitrelay.tests.sync-phase.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        let repoID = addSSHRepo(to: vm, name: "phase-repo")
        vm.triggerSync(repoID: repoID)

        #expect(vm.statuses[repoID] == .syncing)
        #expect(vm.syncPhases[repoID] != nil)
        #expect(vm.syncPhases[repoID]?.kind == .fetchingSource)

        vm.cancelSync(repoID: repoID)
        #expect(vm.syncPhases[repoID] == nil)
        #expect(vm.statuses[repoID] != .syncing)
    }

    @Test func queuedPromotesToSyncingWithPhase() {
        let suite = "gitrelay.tests.sync-phase-queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        var prefs = vm.notificationPreferences.preferences
        prefs.maxConcurrentSyncs = 1
        vm.notificationPreferences.preferences = prefs

        let first = addSSHRepo(to: vm, name: "running")
        let second = addSSHRepo(to: vm, name: "waiting")

        vm.triggerSync(repoID: first)
        vm.triggerSync(repoID: second)

        #expect(vm.statuses[first] == .syncing)
        #expect(vm.syncPhases[first] != nil)
        #expect(vm.statuses[second] == .queued)
        #expect(vm.syncPhases[second] == nil)

        vm.cancelSync(repoID: first)
        #expect(vm.statuses[second] == .syncing)
        #expect(vm.syncPhases[second] != nil)
        #expect(vm.syncPhases[first] == nil)
    }
}
