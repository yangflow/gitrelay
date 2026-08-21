import Foundation
import Testing
@testable import GitRelay

// MARK: - Remote URL → web page (#103)

struct GitRemoteWebURLTests {
    @Test func sshShorthandBecomesTheHTTPSPage() throws {
        let url = try #require(
            GitRemoteWebURL.url(forRemote: "git@github.com:organization/keychord.git")
        )
        #expect(url.absoluteString == "https://github.com/organization/keychord")
    }

    @Test func anSSHURLDropsItsSSHPort() throws {
        let url = try #require(
            GitRemoteWebURL.url(forRemote: "ssh://git@gitea.example.com:2222/team/proj.git")
        )
        #expect(url.absoluteString == "https://gitea.example.com/team/proj")
    }

    @Test func anHTTPSRemoteLosesOnlyItsGitSuffix() throws {
        let url = try #require(
            GitRemoteWebURL.url(forRemote: "https://gitlab.com/team/proj.git")
        )
        #expect(url.absoluteString == "https://gitlab.com/team/proj")
    }

    @Test func anEmbeddedTokenNeverReachesTheBrowser() throws {
        let url = try #require(
            GitRemoteWebURL.url(forRemote: "https://ghp_secretTOKEN@github.com/acme/mirror.git")
        )
        #expect(url.absoluteString == "https://github.com/acme/mirror")
        #expect(!url.absoluteString.contains("ghp_secretTOKEN"))
    }

    @Test func aSelfHostedInstanceKeepsPlainHTTPAndItsWebPort() throws {
        let plain = try #require(GitRemoteWebURL.url(forRemote: "http://git.internal/team/x.git"))
        #expect(plain.absoluteString == "http://git.internal/team/x")

        let ported = try #require(
            GitRemoteWebURL.url(forRemote: "https://gitea.example.com:3000/team/x.git")
        )
        #expect(ported.absoluteString == "https://gitea.example.com:3000/team/x")
    }

    @Test func nestedGroupsSurviveIntact() throws {
        let url = try #require(
            GitRemoteWebURL.url(forRemote: "git@gitlab.com:team/sub/proj.git")
        )
        #expect(url.absoluteString == "https://gitlab.com/team/sub/proj")
    }

    @Test func theHostIsLoweredAndThePathIsLeftAlone() throws {
        let url = try #require(GitRemoteWebURL.url(forRemote: "git@GitHub.com:Acme/Repo.git"))
        #expect(url.absoluteString == "https://github.com/Acme/Repo")
    }

    @Test func aPathOnThisMacIsNotAWebPage() {
        #expect(GitRemoteWebURL.url(forRemote: "/Users/me/Repos/proj-sync") == nil)
        #expect(GitRemoteWebURL.url(forRemote: "~/Repos/proj-sync") == nil)
    }

    @Test func halfAURLNamesNoPage() {
        #expect(GitRemoteWebURL.url(forRemote: "") == nil)
        #expect(GitRemoteWebURL.url(forRemote: "   ") == nil)
        #expect(GitRemoteWebURL.url(forRemote: "git@github.com:") == nil)
        #expect(GitRemoteWebURL.url(forRemote: "https://github.com") == nil)
    }
}

// MARK: - What 打开 does per endpoint (#103)

struct RepoOpenLocationTests {
    private func repo(
        srcURL: String,
        targets: [MirrorTarget]
    ) -> RepoConfig {
        RepoConfig(name: "keychord", srcURL: srcURL, targets: targets)
    }

    @Test func aRemoteSourceOpensItsPage() throws {
        let config = repo(
            srcURL: "git@github.com:organization/keychord.git",
            targets: [MirrorTarget(url: "git@github.com:organization/keychord-mirror.git")]
        )
        let page = try #require(URL(string: "https://github.com/organization/keychord"))
        let source = try #require(RepoOpenLocation.source(of: config))
        #expect(source == .web(page))
        #expect(source.actionTitle == String(localized: "Open"))
    }

    @Test func aSourceOnThisMacIsRevealedInFinder() throws {
        let config = repo(
            srcURL: "/Users/me/Repos/proj-sync",
            targets: [MirrorTarget(url: "git@gitlab.com:team/proj.git")]
        )
        let source = try #require(RepoOpenLocation.source(of: config))
        #expect(source == .revealInFinder(URL(fileURLWithPath: "/Users/me/Repos/proj-sync")))
        #expect(source.actionTitle == String(localized: "Show in Finder"))
    }

    @Test func anArchiveTargetIsRevealedRatherThanBrowsed() throws {
        let target = MirrorTarget(
            kind: .filesystem,
            url: "",
            filesystemPath: "~/Backups/keychord",
            archiveFormat: .tarGz
        )
        let location = try #require(RepoOpenLocation.target(target))
        let expanded = URL(
            fileURLWithPath: NSString(string: "~/Backups/keychord").expandingTildeInPath
        )
        #expect(location == .revealInFinder(expanded))
        #expect(location.actionTitle == String(localized: "Show in Finder"))
    }

    @Test func aRemoteTargetOpensItsPage() throws {
        let page = try #require(URL(string: "https://gitlab.com/team/proj-mirror"))
        let location = try #require(
            RepoOpenLocation.target(MirrorTarget(url: "git@gitlab.com:team/proj-mirror.git"))
        )
        #expect(location == .web(page))
    }

    @Test func aRelativeOrEmptyPathOffersNothing() {
        #expect(RepoOpenLocation.target(MirrorTarget(kind: .filesystem, filesystemPath: "Backups")) == nil)
        #expect(RepoOpenLocation.target(MirrorTarget(kind: .filesystem, filesystemPath: "")) == nil)
        #expect(RepoOpenLocation.target(MirrorTarget(url: "not-a-remote")) == nil)
    }

    @Test func aFileURLTargetIsUnwrappedToItsPath() throws {
        let location = try #require(
            RepoOpenLocation.target(
                MirrorTarget(kind: .filesystem, filesystemPath: "file:///Volumes/Backup/keychord")
            )
        )
        #expect(location == .revealInFinder(URL(fileURLWithPath: "/Volumes/Backup/keychord")))
    }
}

// MARK: - Per-pair scheduled-sync pause (#103)

struct RepoScheduleStateTests {
    private func repo(
        frequency: SyncFrequency = .hour1,
        paused: Bool = false,
        needsCredentials: Bool = false
    ) -> RepoConfig {
        RepoConfig(
            name: "keychord",
            srcURL: "git@github.com:organization/keychord.git",
            dstURL: "git@github.com:organization/keychord-mirror.git",
            frequency: frequency,
            needsCredentials: needsCredentials,
            scheduledSyncPaused: paused
        )
    }

    @Test func aScheduledPairArmsItsTimer() {
        let state = RepoScheduleState.make(repo: repo())
        #expect(state.armsTimer)
        #expect(RepoScheduleState.armsTimer(for: repo()))
        #expect(state.showsPauseToggle)
    }

    @Test func aPausedPairArmsNothingAndSaysSo() {
        let paused = repo(paused: true)
        #expect(!RepoScheduleState.armsTimer(for: paused))

        let state = RepoScheduleState.make(repo: paused, nextFireDate: Date())
        #expect(state.isPaused)
        #expect(state.nextRun == .paused)
        #expect(state.showsPauseToggle)
        #expect(state.toggleTitle == String(localized: "Resume"))
    }

    @Test func aManualPairHasNoScheduleToPause() {
        let state = RepoScheduleState.make(repo: repo(frequency: .manual))
        #expect(!state.armsTimer)
        #expect(state.nextRun == .manualOnly)
        #expect(!state.showsPauseToggle)
        #expect(state.toggleTitle == String(localized: "Pause"))
    }

    /// Setting a paused pair back to 手动 must still leave a way to un-pause it.
    @Test func aPausedManualPairKeepsItsToggle() {
        let state = RepoScheduleState.make(repo: repo(frequency: .manual, paused: true))
        #expect(state.showsPauseToggle)
        #expect(state.nextRun == .paused)
    }

    @Test func aPairWaitingOnCredentialsIsNotScheduled() {
        let state = RepoScheduleState.make(repo: repo(needsCredentials: true), nextFireDate: Date())
        #expect(!state.armsTimer)
        #expect(state.nextRun == .unscheduled)
    }

    @Test func anArmedTimerReportsItsNextRun() {
        let fire = Date().addingTimeInterval(900)
        let state = RepoScheduleState.make(repo: repo(), nextFireDate: fire)
        #expect(state.nextRun == .due(fire))
        #expect(state.nextRun.text().contains(RepoNextRun.timeText(for: fire)))
    }

    @Test func aRunLaterThanTodayCarriesItsDate() {
        let now = Date()
        let tomorrow = now.addingTimeInterval(86_400)
        let sameDay = RepoNextRun.timeText(for: now, now: now)
        let nextDay = RepoNextRun.timeText(for: tomorrow, now: now)
        #expect(sameDay != nextDay)
    }

    @Test func thePauseFlagSurvivesASaveAndLoad() throws {
        let data = try JSONEncoder().encode(repo(paused: true))
        let restored = try JSONDecoder().decode(RepoConfig.self, from: data)
        #expect(restored.scheduledSyncPaused)
    }

    @Test func anUnpausedPairWritesNoPauseKeyAndReadsBackFalse() throws {
        let data = try JSONEncoder().encode(repo())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("scheduledSyncPaused"))

        let restored = try JSONDecoder().decode(RepoConfig.self, from: data)
        #expect(!restored.scheduledSyncPaused)
    }
}

@MainActor
struct ScheduledSyncPauseSchedulerTests {
    private func repo(paused: Bool) -> RepoConfig {
        RepoConfig(
            name: "keychord",
            srcURL: "git@github.com:organization/keychord.git",
            dstURL: "git@github.com:organization/keychord-mirror.git",
            frequency: .min15,
            scheduledSyncPaused: paused
        )
    }

    @Test func theSchedulerRefusesToArmAPausedPair() {
        let scheduler = SyncScheduler()
        defer { scheduler.invalidateAll() }

        var config = repo(paused: false)
        scheduler.schedule(repo: config)
        #expect(scheduler.nextFireDate(for: config.id) != nil)

        config.scheduledSyncPaused = true
        scheduler.reschedule(repo: config)
        #expect(scheduler.nextFireDate(for: config.id) == nil)

        config.scheduledSyncPaused = false
        scheduler.reschedule(repo: config)
        #expect(scheduler.nextFireDate(for: config.id) != nil)
    }

    /// A pair whose frequency is 手动 must not keep a timer from an earlier
    /// frequency just because ``schedule`` was called again.
    @Test func schedulingAManualPairDisarmsAnyStandingTimer() {
        let scheduler = SyncScheduler()
        defer { scheduler.invalidateAll() }

        var config = repo(paused: false)
        scheduler.schedule(repo: config)
        #expect(scheduler.nextFireDate(for: config.id) != nil)

        config.frequency = .manual
        scheduler.schedule(repo: config)
        #expect(scheduler.nextFireDate(for: config.id) == nil)
    }
}

@MainActor
struct ScheduledSyncPauseAppViewModelTests {
    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-pair-pause-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Constants.setBaseDirectoryForTesting(base)
        let vm = AppViewModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            notificationPreferencesStore: NotificationPreferencesStore(defaults: defaults)
        )
        vm.suspendSyncEngineForTesting = true
        // The test machine's power and network state must not stand in for a
        // per-pair pause.
        var prefs = vm.notificationPreferences.preferences
        prefs.pauseOnLowPowerMode = false
        prefs.pauseOnExpensiveNetwork = false
        vm.notificationPreferences.preferences = prefs
        return vm
    }

    private func addScheduledRepo(to vm: AppViewModel) -> UUID {
        let id = UUID()
        vm.addRepo(
            RepoConfig(
                id: id,
                name: "keychord",
                srcURL: "git@github.com:organization/keychord.git",
                dstURL: "git@github.com:organization/keychord-mirror.git",
                frequency: .min15
            )
        )
        return id
    }

    @Test func pausingOnePairStopsItsTimerButNotItsManualSync() {
        let suite = "gitrelay.tests.pair-pause.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        let id = addScheduledRepo(to: vm)
        #expect(!vm.isScheduledSyncPaused(repoID: id))
        #expect(vm.nextFireDate(for: id) != nil)

        vm.toggleScheduledSyncPause(repoID: id)
        #expect(vm.isScheduledSyncPaused(repoID: id))
        #expect(vm.nextFireDate(for: id) == nil)

        // 同步 is still the user's to press.
        vm.triggerSync(repoID: id)
        #expect(vm.inProgressSyncIDs.contains(id))

        vm.cancelSync(repoID: id)
        vm.toggleScheduledSyncPause(repoID: id)
        #expect(!vm.isScheduledSyncPaused(repoID: id))
        #expect(vm.nextFireDate(for: id) != nil)
    }

    @Test func pausingOnePairLeavesTheOtherAlone() {
        let suite = "gitrelay.tests.pair-pause-isolated.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeViewModel(defaults: defaults)

        let paused = addScheduledRepo(to: vm)
        let other = addScheduledRepo(to: vm)

        vm.setScheduledSyncPaused(true, repoID: paused)

        #expect(vm.nextFireDate(for: paused) == nil)
        #expect(vm.nextFireDate(for: other) != nil)
        // The per-pair pause is not the app-wide one behind the sidebar footer.
        #expect(!vm.isScheduledSyncManuallyPaused)
        #expect(vm.scheduledSyncPauseReason == nil)
    }
}

// MARK: - 复制这次失败 payload (#103)

struct SyncFailureCopyTests {
    private var repo: RepoConfig {
        RepoConfig(
            name: "keychord",
            srcURL: "git@github.com:organization/keychord.git",
            dstURL: "git@github.com:organization/keychord-mirror.git"
        )
    }

    @Test func thePayloadNamesThePairAndTheError() {
        let text = SyncFailureCopy.text(
            repo: repo,
            message: "Authentication failed for github.com.",
            logLines: ["fatal: could not read Username"],
            failedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(text.contains("keychord"))
        #expect(text.contains("git@github.com:organization/keychord.git"))
        #expect(text.contains("git@github.com:organization/keychord-mirror.git"))
        #expect(text.contains("Authentication failed for github.com."))
        #expect(text.contains("fatal: could not read Username"))
        #expect(text.contains("2023-11-14"))
    }

    @Test func aTokenInTheMessageOrTheLogIsRedacted() {
        let text = SyncFailureCopy.text(
            repo: repo,
            message: "fatal: repository 'https://ghp_secretTOKEN@github.com/acme/x.git' not found",
            logLines: [
                "» git push --mirror https://ghp_otherTOKEN@github.com/acme/x.git",
                "remote: Invalid username or password"
            ]
        )

        #expect(!text.contains("ghp_secretTOKEN"))
        #expect(!text.contains("ghp_otherTOKEN"))
        #expect(text.contains("https://****@github.com"))
    }

    @Test func aTokenPastedIntoTheSourceURLIsRedactedToo() {
        var tokenized = repo
        tokenized.srcURL = "https://ghp_inTheConfig@github.com/organization/keychord.git"

        let text = SyncFailureCopy.text(repo: tokenized, message: "Network unreachable")

        #expect(!text.contains("ghp_inTheConfig"))
        #expect(text.contains("https://****@github.com"))
    }

    @Test func aLongLogIsCutToItsTailAndSaysSo() {
        let lines = (1...(SyncFailureCopy.maxLogLines + 100)).map { "line \($0)" }
        let text = SyncFailureCopy.text(repo: repo, message: "Push rejected", logLines: lines)

        #expect(text.contains(String(localized: "Showing the last \(SyncFailureCopy.maxLogLines) log lines")))
        #expect(!text.contains("line 100"))
        #expect(text.contains("line \(lines.count)"))
    }

    @Test func aFailureWithoutALogSkipsTheLogSection() {
        let text = SyncFailureCopy.text(repo: repo, message: "Push rejected")

        #expect(!text.contains(String(localized: "Log:")))
        #expect(text.contains("Push rejected"))
    }
}

// MARK: - 账号 line (#103)

struct RepoAccountLineTests {
    @Test func theDefaultAccountShowsOnlyTheProviderName() {
        #expect(
            RepoAccountLine.displayName(provider: .github, label: ProviderAccount.defaultLabel)
                == "GitHub"
        )
    }

    @Test func aLabelledAccountReadsProviderThenLabel() {
        #expect(RepoAccountLine.displayName(provider: .github, label: "工作") == "GitHub 工作")
        #expect(RepoAccountLine.displayName(provider: .gitlab, label: "team") == "GitLab team")
        // Gitea's long display name (with the Gitee gloss) has no business inline.
        #expect(RepoAccountLine.displayName(provider: .gitea, label: "home") == "Gitea home")
    }

    @Test func repeatedAccountsCollapseIntoOneLine() throws {
        let line = try #require(RepoAccountLine.make(names: ["GitHub 工作", "GitHub 工作"]))
        #expect(line.names == ["GitHub 工作"])
        #expect(line.text.contains("GitHub 工作"))
    }

    @Test func aCrossProviderPairNamesBothAccounts() throws {
        let line = try #require(RepoAccountLine.make(names: ["GitHub 工作", "GitLab team"]))
        #expect(line.names == ["GitHub 工作", "GitLab team"])
    }

    @Test func nothingSavedMeansNoLine() {
        #expect(RepoAccountLine.make(names: []) == nil)
        #expect(RepoAccountLine.make(names: ["", "   "]) == nil)
    }
}
