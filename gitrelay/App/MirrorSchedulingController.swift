import AppKit
import Foundation
import Observation

/// Owns frequency-driven sync and verification scheduling. It may request
/// operations, but operation admission and execution remain owned by
/// `MirrorOperationsController`.
@MainActor
@Observable
final class MirrorSchedulingController {
    let library: MirrorLibraryModel
    let operations: MirrorOperationsController
    let environmentMonitor: SyncEnvironmentMonitor
    let quietHoursMonitor: QuietHoursMonitor

    @ObservationIgnored
    var onStateChange: () -> Void = {}

    @ObservationIgnored
    private let syncScheduler: SyncScheduler
    @ObservationIgnored
    private let verificationScheduler: VerificationScheduler
    @ObservationIgnored
    private var wakeObserver: NSObjectProtocol?

    private var notificationPreferences: NotificationPreferences = .default
    private var verificationPreferences: VerificationPreferences = .default
    private var quietHoursCatchUp = QuietHoursCatchUpTracker()
    private var missedRunCatchUp = MissedRunCatchUpProgress()
    private var lastScheduledSkipLogAt: Date?
    private var wasScheduledSyncPaused = false
    private var didStart = false

    init(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        syncScheduler: SyncScheduler? = nil,
        verificationScheduler: VerificationScheduler? = nil,
        environmentMonitor: SyncEnvironmentMonitor? = nil,
        quietHoursMonitor: QuietHoursMonitor? = nil
    ) {
        self.library = library
        self.operations = operations
        self.syncScheduler = syncScheduler ?? SyncScheduler()
        self.verificationScheduler = verificationScheduler ?? VerificationScheduler()
        self.environmentMonitor = environmentMonitor ?? SyncEnvironmentMonitor()
        self.quietHoursMonitor = quietHoursMonitor ?? QuietHoursMonitor()

        self.syncScheduler.onFire = { [weak self] id in
            self?.handleScheduledSyncFire(mirrorID: id)
        }
        self.verificationScheduler.onFire = { [weak self] in
            self?.runScheduledVerificationSample()
        }
        self.environmentMonitor.onEnvironmentChange = { [weak self] in
            self?.handleScheduledPauseTransition()
        }
        self.quietHoursMonitor.onTransition = { [weak self] in
            self?.handleScheduledPauseTransition()
        }
    }

    var pauseReason: SyncPauseReason? {
        _ = quietHoursMonitor.isActive
        return notificationPreferences.pausePolicy.pauseReason(
            isLowPowerMode: environmentMonitor.isLowPowerModeEnabled,
            isExpensiveNetwork: environmentMonitor.isExpensiveNetwork,
            date: quietHoursMonitor.now(),
            calendar: quietHoursMonitor.calendar
        )
    }

    var menuBarStatusLine: MenuBarStatusLine? {
        MenuBarStatusLine.make(
            pauseReason: pauseReason,
            missedRuns: missedRunCatchUp.isCatchingUp ? missedRunCatchUp.missedRunCount : 0
        )
    }

    func start(
        notificationPreferences: NotificationPreferences,
        verificationPreferences: VerificationPreferences
    ) {
        self.notificationPreferences = notificationPreferences
        self.verificationPreferences = verificationPreferences
        guard !didStart else {
            updateNotificationPreferences(notificationPreferences)
            updateVerificationPreferences(verificationPreferences)
            return
        }
        didStart = true
        library.mirrors.forEach(schedule)
        verificationScheduler.schedule(frequency: verificationPreferences.frequency)
        environmentMonitor.start()
        quietHoursMonitor.start(settings: notificationPreferences.quietHours)
        wasScheduledSyncPaused = pauseReason != nil
        observeWake()
    }

    func stop() {
        syncScheduler.invalidateAll()
        verificationScheduler.invalidate()
        environmentMonitor.stop()
        quietHoursMonitor.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        didStart = false
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) {
        notificationPreferences = preferences
        quietHoursMonitor.update(settings: preferences.quietHours)
        handleScheduledPauseTransition()
    }

    func updateVerificationPreferences(_ preferences: VerificationPreferences) {
        verificationPreferences = preferences
        verificationScheduler.reschedule(frequency: preferences.frequency)
    }

    func register(_ mirror: MirrorSnapshot) {
        schedule(mirror)
    }

    func update(_ mirror: MirrorSnapshot) {
        syncScheduler.reschedule(
            plan: mirror.plan,
            needsCredentials: mirror.needsCredentials
        )
    }

    func unregister(mirrorID: UUID) {
        syncScheduler.deschedule(repoID: mirrorID)
        quietHoursCatchUp.clear(repoID: mirrorID)
        missedRunCatchUp.noteFinished(repoID: mirrorID)
        onStateChange()
    }

    func deschedule(mirrorID: UUID) {
        syncScheduler.deschedule(repoID: mirrorID)
    }

    func resetForCurrentLibrary() {
        syncScheduler.invalidateAll()
        quietHoursCatchUp = QuietHoursCatchUpTracker()
        missedRunCatchUp = MissedRunCatchUpProgress()
        library.mirrors.forEach(schedule)
        onStateChange()
    }

    func nextFireDate(mirrorID: UUID) -> Date? {
        syncScheduler.nextFireDate(for: mirrorID)
    }

    func nextVerificationFireDate() -> Date? {
        verificationScheduler.nextFireDate()
    }

    func noteOperationSettled(mirrorID: UUID) {
        missedRunCatchUp.noteFinished(repoID: mirrorID)
        onStateChange()
    }

    /// Runs frequency debt after wake or app activation. Timers do not replay
    /// ticks that elapsed while the Mac slept.
    func catchUpMissedScheduledRuns(now: Date = Date()) {
        guard pauseReason == nil else { return }
        let expectations = library.mirrors.compactMap {
            syncScheduler.runExpectation(for: $0.id)
        }
        let outcome = MissedScheduledRuns.evaluate(expectations: expectations, now: now)
        guard outcome.hasMissedRuns else { return }

        var admitted: [UUID] = []
        for id in outcome.dueRepoIDs {
            operations.triggerSync(mirrorID: id)
            if operations.inProgressSyncIDs.contains(id) || operations.isQueued(id) {
                admitted.append(id)
            }
            if let mirror = library.mirror(id: id) {
                update(mirror)
            }
        }
        missedRunCatchUp.begin(
            missedRunCount: outcome.missedRunCount,
            repoIDs: admitted
        )
        onStateChange()
    }

    private func schedule(_ mirror: MirrorSnapshot) {
        syncScheduler.schedule(
            plan: mirror.plan,
            needsCredentials: mirror.needsCredentials
        )
    }

    private func handleScheduledSyncFire(mirrorID: UUID) {
        if let reason = pauseReason {
            if reason.isQuietHours {
                quietHoursCatchUp.noteScheduledSkip(repoID: mirrorID)
                logQuietHoursSkipIfNeeded()
            }
            wasScheduledSyncPaused = true
            onStateChange()
            return
        }
        quietHoursCatchUp.clear(repoID: mirrorID)
        operations.triggerSync(mirrorID: mirrorID)
    }

    private func handleScheduledPauseTransition() {
        let paused = pauseReason != nil
        if paused {
            wasScheduledSyncPaused = true
            onStateChange()
            return
        }
        guard wasScheduledSyncPaused || !quietHoursCatchUp.pendingRepoIDs.isEmpty else { return }
        wasScheduledSyncPaused = false
        let ids = quietHoursCatchUp.takePendingCatchUp()
        for id in ids {
            operations.triggerSync(mirrorID: id)
            if let mirror = library.mirror(id: id) {
                update(mirror)
            }
        }
        onStateChange()
    }

    private func runScheduledVerificationSample() {
        let sample = VerificationSampler.sample(
            from: library.plans,
            count: verificationPreferences.sampleSize
        )
        sample.forEach { operations.triggerVerify(mirrorID: $0.id) }
    }

    private func logQuietHoursSkipIfNeeded() {
        let now = quietHoursMonitor.now()
        if let last = lastScheduledSkipLogAt, now.timeIntervalSince(last) < 3600 {
            return
        }
        lastScheduledSkipLogAt = now
        print("GitRelay: skipped scheduled sync during quiet hours")
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.catchUpMissedScheduledRuns()
            }
        }
    }
}
