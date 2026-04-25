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
}
