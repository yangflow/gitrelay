import Foundation
import Testing
@testable import GitRelay

// MARK: - Preflight decision table (#101)

struct AddPreflightDecisionTests {
    private let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")

    @Test func bothSidesReachableIsReady() {
        #expect(AddPreflight.decide(source: .reachable, destination: .reachable) == .ready)
    }

    @Test func missingDestinationOffersToCreateIt() {
        let decision = AddPreflight.decide(source: .reachable, destination: .missing)

        #expect(decision == .destinationMissing)
        #expect(decision.primaryAction == .createDestination)
        #expect(decision.hasCaption)
        #expect(!decision.offersOpenExistingPair)
    }

    @Test func missingSourceIsReportedButNotCreatable() {
        let decision = AddPreflight.decide(source: .missing, destination: .reachable)

        #expect(decision == .sourceMissing)
        #expect(decision.primaryAction == .add)
    }

    @Test func refusedCredentialsNameTheSideThatRefused() {
        #expect(
            AddPreflight.decide(source: .authenticationFailed, destination: .reachable)
                == .authenticationFailed(.source)
        )
        #expect(
            AddPreflight.decide(source: .reachable, destination: .authenticationFailed)
                == .authenticationFailed(.destination)
        )
    }

    @Test func refusedSourceCredentialsOutrankAMissingDestination() {
        // A refused credential explains a "missing" answer, so do not offer to create.
        let decision = AddPreflight.decide(source: .authenticationFailed, destination: .missing)

        #expect(decision == .authenticationFailed(.source))
        #expect(decision.primaryAction == .add)
    }

    @Test func refusedDestinationCredentialsOutrankAMissingDestination() {
        let decision = AddPreflight.decide(
            source: .reachable,
            destination: .authenticationFailed
        )

        #expect(decision == .authenticationFailed(.destination))
        #expect(decision.primaryAction == .add)
    }

    @Test func duplicatePairWinsOverEveryProbeAnswer() throws {
        let id = try #require(existingID)
        let cases: [(AddPreflightProbeResult, AddPreflightProbeResult)] = [
            (.reachable, .reachable),
            (.reachable, .missing),
            (.authenticationFailed, .missing),
            (.pending, .pending)
        ]

        for (source, destination) in cases {
            let decision = AddPreflight.decide(
                source: source,
                destination: destination,
                duplicateRepoID: id
            )
            #expect(decision == .duplicatePair(existingRepoID: id))
            #expect(decision.primaryAction == .addAnyway)
            #expect(decision.offersOpenExistingPair)
            #expect(decision.existingPairID == id)
        }
    }

    @Test func unfinishedProbesStayQuiet() {
        let decision = AddPreflight.decide(source: .pending, destination: .reachable)

        #expect(decision == .idle)
        #expect(!decision.hasCaption)
        #expect(decision.primaryAction == .add)
    }

    @Test func skippedSidesCountAsNothingToSay() {
        #expect(AddPreflight.decide(source: .skipped, destination: .skipped) == .ready)
        #expect(AddPreflight.decide(source: .reachable, destination: .skipped) == .ready)
    }

    @Test func unreachableSideIsNamedAfterDefiniteAnswers() {
        #expect(
            AddPreflight.decide(source: .unreachable, destination: .reachable)
                == .unreachable(.source)
        )
        #expect(
            AddPreflight.decide(source: .reachable, destination: .unreachable)
                == .unreachable(.destination)
        )
        // A definite "missing" still wins over a flaky source connection.
        #expect(AddPreflight.decide(source: .unreachable, destination: .missing) == .destinationMissing)
    }
}

// MARK: - Preflight caption copy

struct AddPreflightCopyTests {
    @Test func destinationProviderLabelMatchesTheHost() {
        #expect(
            AddPreflightCopy.destinationProviderLabel(
                destinationURL: "https://gitlab.com/yangflow/keychord.git"
            ) == "GitLab"
        )
        #expect(
            AddPreflightCopy.destinationProviderLabel(
                destinationURL: "git@github.com:yangflow/keychord.git"
            ) == "GitHub"
        )
        #expect(
            AddPreflightCopy.destinationProviderLabel(
                destinationURL: "https://git.example.com/team/keychord.git"
            ) == "git.example.com"
        )
        #expect(AddPreflightCopy.destinationProviderLabel(destinationURL: "not-a-url") == nil)
    }

    @Test func missingDestinationCaptionNamesTheDestinationProvider() throws {
        let caption = try #require(
            AddPreflightCopy.caption(
                for: .destinationMissing,
                destinationURL: "https://gitlab.com/yangflow/keychord.git"
            )
        )

        #expect(caption.contains("GitLab"))
        #expect(!caption.contains("GitHub"))
    }

    @Test func missingDestinationCaptionFallsBackWithoutAHost() throws {
        let caption = try #require(
            AddPreflightCopy.caption(for: .destinationMissing, destinationURL: "")
        )

        #expect(caption.contains("does not exist"))
    }

    @Test func duplicateCaptionPointsAtBothWaysOut() throws {
        let caption = try #require(
            AddPreflightCopy.caption(
                for: .duplicatePair(existingRepoID: UUID()),
                destinationURL: "https://gitlab.com/yangflow/keychord.git"
            )
        )

        #expect(caption == "This mirror already exists. Open it or change the target.")
    }

    @Test func credentialCaptionsNameTheSide() throws {
        let source = try #require(
            AddPreflightCopy.caption(for: .authenticationFailed(.source), destinationURL: "")
        )
        let destination = try #require(
            AddPreflightCopy.caption(for: .authenticationFailed(.destination), destinationURL: "")
        )

        #expect(source.contains("source"))
        #expect(source.contains("token"))
        #expect(destination.contains("destination"))
        #expect(source != destination)
    }

    @Test func quietStatesHaveNoCaption() {
        #expect(AddPreflightCopy.caption(for: .idle, destinationURL: "") == nil)
        #expect(AddPreflightCopy.caption(for: .ready, destinationURL: "") == nil)
    }

    @Test func createTokenCaptionNamesTheProvider() {
        let caption = AddPreflightCopy.missingCreateTokenCaption(
            destinationURL: "https://gitlab.com/yangflow/keychord.git"
        )

        #expect(caption.contains("GitLab"))
    }

    @Test func buttonTitlesAreEnglishInTheDefaultLocale() {
        #expect(AddPreflightCopy.createAndStartSyncTitle == "Create and Start Sync")
        #expect(AddPreflightCopy.openExistingTitle == "Open the Existing One")
        #expect(AddPreflightCopy.addAnywayTitle == "Add Anyway")
    }
}

// MARK: - Duplicate pair detection

struct MirrorPairIdentityTests {
    @Test func sshAndHTTPSFormsOfOneRepoMatch() {
        let ssh = GitRemoteIdentity.remote("git@github.com:yangflow/keychord.git")
        let https = GitRemoteIdentity.remote("https://github.com/YangFlow/keychord")

        #expect(ssh != nil)
        #expect(ssh == https)
    }

    @Test func differentHostsDoNotMatch() {
        #expect(
            GitRemoteIdentity.remote("git@github.com:yangflow/keychord.git")
                != GitRemoteIdentity.remote("git@gitlab.com:yangflow/keychord.git")
        )
    }

    @Test func nonRemoteStringsFallBackToAPath() {
        #expect(GitRemoteIdentity.remote("/Volumes/Backup/archives") == nil)
        #expect(
            GitRemoteIdentity.any("/Volumes/Backup/archives/")
                == GitRemoteIdentity.any("/Volumes/Backup/archives")
        )
    }

    @Test func savedPairIsFoundRegardlessOfURLForm() {
        let saved = MirrorSnapshot(
            name: "keychord",
            srcURL: "https://github.com/yangflow/keychord.git",
            dstURL: "git@gitlab.com:yangflow/keychord.git"
        )

        let match = MirrorPairDuplicates.existingRepoID(
            source: "git@github.com:yangflow/keychord.git",
            target: "https://gitlab.com/yangflow/keychord.git",
            in: [saved]
        )

        #expect(match == saved.id)
    }

    @Test func aDifferentTargetIsNotADuplicate() {
        let saved = MirrorSnapshot(
            name: "keychord",
            srcURL: "git@github.com:yangflow/keychord.git",
            dstURL: "git@gitlab.com:yangflow/keychord.git"
        )

        let match = MirrorPairDuplicates.existingRepoID(
            source: "git@github.com:yangflow/keychord.git",
            target: "git@gitlab.com:yangflow/keychord-backup.git",
            in: [saved]
        )

        #expect(match == nil)
    }

    @Test func anyTargetOfAMultiTargetRepoCounts() {
        let saved = MirrorSnapshot(
            name: "keychord",
            srcURL: "git@github.com:yangflow/keychord.git",
            targets: [
                MirrorTarget(url: "git@gitlab.com:yangflow/keychord.git"),
                MirrorTarget(url: "git@gitea.example.com:yangflow/keychord.git", enabled: false)
            ]
        )

        #expect(
            MirrorPairDuplicates.existingRepoID(
                source: "git@github.com:yangflow/keychord.git",
                target: "https://gitea.example.com/yangflow/keychord",
                in: [saved]
            ) == saved.id
        )
    }

    @Test func theRepoBeingEditedDoesNotMatchItself() {
        let saved = MirrorSnapshot(
            name: "keychord",
            srcURL: "git@github.com:yangflow/keychord.git",
            dstURL: "git@gitlab.com:yangflow/keychord.git"
        )

        let match = MirrorPairDuplicates.existingRepoID(
            source: "git@github.com:yangflow/keychord.git",
            target: "git@gitlab.com:yangflow/keychord.git",
            in: [saved],
            excluding: saved.id
        )

        #expect(match == nil)
    }

    @Test func archiveTargetsComparedByPath() {
        let saved = MirrorSnapshot(
            name: "keychord",
            srcURL: "git@github.com:yangflow/keychord.git",
            targets: [
                MirrorTarget(
                    kind: .filesystem,
                    filesystemPath: "/Volumes/Backup/archives"
                )
            ]
        )

        #expect(
            MirrorPairDuplicates.existingRepoID(
                source: "git@github.com:yangflow/keychord.git",
                target: "/Volumes/Backup/archives",
                in: [saved]
            ) == saved.id
        )
    }
}

// MARK: - Probe failure classification

struct AddPreflightProbeClassifierTests {
    @Test func missingRepositoryWording() {
        let messages = [
            "ERROR: Repository not found.",
            "remote: Repository not found.\nfatal: repository 'https://github.com/a/b.git/' not found",
            "remote: The project you were looking for could not be found or you don't have permission to view it.",
            "fatal: '/tmp/nope' does not appear to be a git repository"
        ]

        for message in messages {
            #expect(AddPreflightProbeClassifier.result(forFailureMessage: message) == .missing)
        }
    }

    @Test func refusedCredentialWording() {
        let messages = [
            "git@github.com: Permission denied (publickey).",
            "remote: HTTP Basic: Access denied. The provided password or token is incorrect.",
            "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
            "fatal: Authentication failed for 'https://gitlab.com/a/b.git/'",
            "fatal: unable to access 'https://gitea.example.com/a/b.git/': The requested URL returned error: 403"
        ]

        for message in messages {
            #expect(
                AddPreflightProbeClassifier.result(forFailureMessage: message) == .authenticationFailed
            )
        }
    }

    @Test func networkWording() {
        let messages = [
            "fatal: unable to access 'https://nope.example/a.git/': Could not resolve host: nope.example",
            "ssh: connect to host gitea.example.com port 22: Connection refused"
        ]

        for message in messages {
            #expect(AddPreflightProbeClassifier.result(forFailureMessage: message) == .unreachable)
        }
    }

    @Test func unrecognizedFailureStaysUnreachableRatherThanPromisingACreate() {
        #expect(
            AddPreflightProbeClassifier.result(forFailureMessage: "fatal: something new") == .unreachable
        )
    }
}

// MARK: - Probe command shaping

struct GitRemoteExistenceProbeTests {
    @Test func probeNeverWaitsForAPrompt() {
        let env = GitRemoteExistenceProbe.environment(
            url: "git@github.com:yangflow/keychord.git",
            credentials: RemoteProbeCredentials(mode: .sshAgent)
        )

        #expect(env["GIT_TERMINAL_PROMPT"] == "0")
        #expect(env["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true)
    }

    @Test func sshKeyModePassesTheKeyPath() {
        let env = GitRemoteExistenceProbe.environment(
            url: "git@github.com:yangflow/keychord.git",
            credentials: RemoteProbeCredentials(mode: .sshKey, sshKeyPath: "/keys/id_ed25519")
        )

        #expect(env["GIT_SSH_COMMAND"]?.contains("-i '/keys/id_ed25519'") == true)
    }

    @Test func sshKeyPathIsOneShellArgument() {
        let path = "/keys/id; touch /tmp/gitrelay-injected #"
        let env = GitRemoteExistenceProbe.environment(
            url: "git@github.com:yangflow/keychord.git",
            credentials: RemoteProbeCredentials(mode: .sshKey, sshKeyPath: path)
        )

        #expect(
            env["GIT_SSH_COMMAND"]
                == "ssh -i '/keys/id; touch /tmp/gitrelay-injected #' -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
        )
    }

    @Test func sshKeyPathEscapesSingleQuotes() {
        #expect(
            GitSSHCommand.usingPrivateKey(at: "/keys/alice's key")
                == "ssh -i '/keys/alice'\\''s key' -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
        )
    }

    @Test func httpsTokenTravelsInTheURLUserinfo() {
        let url = GitRemoteExistenceProbe.probeURL(
            url: "https://gitlab.com/yangflow/keychord.git",
            credentials: RemoteProbeCredentials(mode: .httpsToken, token: "glpat-xyz")
        )

        #expect(url == "https://glpat-xyz@gitlab.com/yangflow/keychord.git")
    }

    @Test func sshURLsAndBlankTokensAreLeftAlone() {
        let ssh = GitRemoteExistenceProbe.probeURL(
            url: "git@gitlab.com:yangflow/keychord.git",
            credentials: RemoteProbeCredentials(mode: .httpsToken, token: "glpat-xyz")
        )
        let noToken = GitRemoteExistenceProbe.probeURL(
            url: "https://gitlab.com/yangflow/keychord.git",
            credentials: RemoteProbeCredentials(mode: .httpsToken)
        )

        #expect(ssh == "git@gitlab.com:yangflow/keychord.git")
        #expect(noToken == "https://gitlab.com/yangflow/keychord.git")
    }
}

// MARK: - Preflight state machine

/// Records what it was asked and answers from a fixed table.
private final class StubRemoteProbe: RemoteExistenceProbing, @unchecked Sendable {
    private let results: [String: AddPreflightProbeResult]
    private let lock = NSLock()
    private var recorded: [String] = []

    init(results: [String: AddPreflightProbeResult]) {
        self.results = results
    }

    var probedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func probe(url: String, credentials: RemoteProbeCredentials) async -> AddPreflightProbeResult {
        lock.lock()
        recorded.append(url)
        lock.unlock()
        return results[url] ?? .reachable
    }
}

@MainActor
struct AddRepoPreflightViewModelTests {
    private let source = "git@github.com:yangflow/keychord.git"
    private let destination = "https://gitlab.com/yangflow/keychord.git"

    private func makeViewModel(
        probe: StubRemoteProbe
    ) -> AddRepoPreflightViewModel {
        AddRepoPreflightViewModel(
            probe: probe,
            debounce: .zero,
            destinationPlan: { _ in nil }
        )
    }

    private func input(source: String, destination: String) -> AddPreflightInput {
        AddPreflightInput(sourceURL: source, destinationURL: destination)
    }

    @Test func missingDestinationTurnsThePrimaryButtonIntoCreate() async {
        let probe = StubRemoteProbe(results: [destination: .missing])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [])
        await vm.probeNow()

        #expect(vm.decision == .destinationMissing)
        #expect(vm.primaryAction == .createDestination)
        #expect(vm.caption?.contains("GitLab") == true)
    }

    @Test func refusedDestinationCredentialsUseTheSameCaptionSlot() async {
        let probe = StubRemoteProbe(results: [destination: .authenticationFailed])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [])
        await vm.probeNow()

        #expect(vm.decision == .authenticationFailed(.destination))
        #expect(vm.primaryAction == .add)
        #expect(vm.caption != nil)
    }

    @Test func bothSidesReachableSaysNothing() async {
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [])
        await vm.probeNow()

        #expect(vm.decision == .ready)
        #expect(vm.caption == nil)
    }

    @Test func duplicatePairAnswersWithoutTouchingTheNetwork() async {
        let saved = MirrorSnapshot(name: "keychord", srcURL: source, dstURL: destination)
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [saved])

        #expect(vm.decision == .duplicatePair(existingRepoID: saved.id))
        #expect(vm.existingPairID == saved.id)
        #expect(vm.primaryAction == .addAnyway)
        #expect(probe.probedURLs.isEmpty)
    }

    @Test func changingTheTargetClearsTheDuplicateState() async {
        let saved = MirrorSnapshot(name: "keychord", srcURL: source, dstURL: destination)
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [saved])
        vm.update(
            input(source: source, destination: "https://gitlab.com/yangflow/keychord-backup.git"),
            existingRepos: [saved]
        )
        await vm.probeNow()

        #expect(vm.decision == .ready)
        #expect(!vm.offersOpenExistingPair)
    }

    @Test func archiveTargetsAreNotProbed() async {
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)
        var draft = input(source: source, destination: "/Volumes/Backup/archives")
        draft.destinationIsFilesystem = true

        vm.update(draft, existingRepos: [])
        await vm.probeNow()

        #expect(probe.probedURLs == [source])
        #expect(vm.decision == .ready)
    }

    @Test func halfTypedURLsStayQuiet() async {
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: "git@gith", destination: ""), existingRepos: [])
        await vm.probeNow()

        #expect(probe.probedURLs.isEmpty)
        #expect(vm.decision == .ready)
        #expect(vm.caption == nil)
    }

    @Test func aURLWithoutARepositoryNameIsNotOfferedForCreation() async {
        let probe = StubRemoteProbe(results: ["https://gitlab.com/yangflow": .missing])
        let vm = makeViewModel(probe: probe)

        vm.update(
            input(source: source, destination: "https://gitlab.com/yangflow"),
            existingRepos: []
        )
        await vm.probeNow()

        #expect(probe.probedURLs == [source])
        #expect(vm.decision == .ready)
    }

    @Test func savingStopsThePreflightFromSpeakingAgain() async {
        let saved = MirrorSnapshot(name: "keychord", srcURL: source, dstURL: destination)
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [])
        vm.finish()
        // The repository the sheet just added must not read back as a duplicate.
        vm.update(input(source: source, destination: destination), existingRepos: [saved])

        #expect(!vm.offersOpenExistingPair)
    }

    @Test func creatingWithoutASavedTokenExplainsItselfAndKeepsTheSheet() async {
        let probe = StubRemoteProbe(results: [destination: .missing])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [])
        await vm.probeNow()
        let maySave = await vm.prepareDestinationForSave()

        #expect(!maySave)
        #expect(vm.caption?.contains("GitLab") == true)
        #expect(vm.caption?.contains("token") == true)
    }

    @Test func statesOtherThanMissingDestinationSaveStraightAway() async {
        let probe = StubRemoteProbe(results: [:])
        let vm = makeViewModel(probe: probe)

        vm.update(input(source: source, destination: destination), existingRepos: [])
        await vm.probeNow()
        let maySave = await vm.prepareDestinationForSave()

        #expect(maySave)
    }

    @Test func cancelStopsThePendingProbe() async {
        let probe = StubRemoteProbe(results: [:])
        let vm = AddRepoPreflightViewModel(
            probe: probe,
            debounce: .seconds(30),
            destinationPlan: { _ in nil }
        )

        vm.update(input(source: source, destination: destination), existingRepos: [])
        vm.cancel()

        #expect(vm.decision == .idle)
        #expect(probe.probedURLs.isEmpty)
    }
}

// MARK: - Destination host token resolution

struct ProviderHostTokenTests {
    @Test func hostsNormalizeAcrossSchemeAndTrailingSlash() {
        #expect(ProviderHostToken.normalizedHost("https://gitlab.example.com/") == "gitlab.example.com")
        #expect(ProviderHostToken.normalizedHost("GitLab.Example.com") == "gitlab.example.com")
        #expect(ProviderHostToken.normalizedHost("http://gitea.example.com/api/v1") == "gitea.example.com")
        #expect(ProviderHostToken.normalizedHost("  ") == "")
    }
}
