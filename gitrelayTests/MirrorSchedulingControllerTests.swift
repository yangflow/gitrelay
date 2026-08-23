import Foundation
import Testing
@testable import GitRelay

@MainActor
@Suite(.serialized)
struct MirrorSchedulingControllerTests {
    private struct Fixture {
        let directory: URL
        let library: MirrorLibraryModel
        let operations: MirrorOperationsController
        let syncScheduler: SyncScheduler
        let verificationScheduler: VerificationScheduler
        let controller: MirrorSchedulingController

        @MainActor
        init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitrelay-scheduling-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            library = MirrorLibraryModel(
                planStore: MirrorPlanStore(fileURL: directory.appendingPathComponent("mirrors.json")),
                stateStore: MirrorStateStore(fileURL: directory.appendingPathComponent("mirror-state.json")),
                runStore: MirrorRunStore(directoryURL: directory.appendingPathComponent("logs")),
                credentialProbe: .alwaysPresent
            )
            operations = MirrorOperationsController(
                library: library,
                credentialProbe: .alwaysPresent
            )
            operations.suspendSyncEngineForTesting = true
            syncScheduler = SyncScheduler()
            syncScheduler.now = { now }
            verificationScheduler = VerificationScheduler()
            controller = MirrorSchedulingController(
                library: library,
                operations: operations,
                syncScheduler: syncScheduler,
                verificationScheduler: verificationScheduler,
                environmentMonitor: SyncEnvironmentMonitor(
                    isLowPowerModeEnabled: false,
                    isExpensiveNetwork: false
                ),
                quietHoursMonitor: QuietHoursMonitor()
            )
            operations.onSyncSettled = { [weak controller] mirrorID in
                controller?.noteOperationSettled(mirrorID: mirrorID)
            }
        }

        @MainActor
        func remove() {
            controller.stop()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func mirror(
        name: String = "mirror",
        frequency: SyncFrequency = .min15,
        needsCredentials: Bool = false,
        scheduledSyncPaused: Bool = false
    ) -> MirrorSnapshot {
        MirrorSnapshot(
            name: name,
            srcURL: "git@github.com:acme/\(name).git",
            dstURL: "git@gitlab.com:acme/\(name).git",
            frequency: frequency,
            needsCredentials: needsCredentials,
            scheduledSyncPaused: scheduledSyncPaused
        )
    }

    @Test func registrationOwnsTimerLifecycleForTheMirror() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try Fixture(now: now)
        defer { fixture.remove() }
        var value = mirror()
        try fixture.library.add(value)

        fixture.controller.register(value)
        #expect(fixture.controller.nextFireDate(mirrorID: value.id) != nil)

        value.scheduledSyncPaused = true
        try fixture.library.update(value)
        fixture.controller.update(value)
        #expect(fixture.controller.nextFireDate(mirrorID: value.id) == nil)

        value.scheduledSyncPaused = false
        value.frequency = .manual
        try fixture.library.update(value)
        fixture.controller.update(value)
        #expect(fixture.controller.nextFireDate(mirrorID: value.id) == nil)

        value.frequency = .hour1
        try fixture.library.update(value)
        fixture.controller.update(value)
        #expect(fixture.controller.nextFireDate(mirrorID: value.id) != nil)

        fixture.controller.unregister(mirrorID: value.id)
        #expect(fixture.controller.nextFireDate(mirrorID: value.id) == nil)
    }

    @Test func credentialGatedMirrorNeverReceivesATimer() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let value = mirror(needsCredentials: true)
        try fixture.library.add(value)

        fixture.controller.register(value)

        #expect(fixture.controller.nextFireDate(mirrorID: value.id) == nil)
    }

    @Test func missedRunsAreAdmittedOnceAndRemainVisibleUntilTheOperationSettles() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try Fixture(now: now)
        defer { fixture.remove() }
        let value = mirror()
        try fixture.library.add(value)
        fixture.controller.register(value)

        fixture.controller.catchUpMissedScheduledRuns(
            now: now.addingTimeInterval(2_700 + MissedScheduledRuns.graceInterval)
        )

        #expect(fixture.operations.inProgressSyncIDs == [value.id])
        #expect(fixture.controller.menuBarStatusLine == .catchingUp(missedRuns: 3))

        fixture.operations.cancelSync(mirrorID: value.id)
        #expect(fixture.operations.inProgressSyncIDs.isEmpty)
        #expect(fixture.controller.menuBarStatusLine == nil)
    }

    @Test func globalPausePreventsWakeCatchUpAndOutranksProgressCopy() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try Fixture(now: now)
        defer { fixture.remove() }
        let value = mirror()
        try fixture.library.add(value)
        fixture.controller.register(value)
        var preferences = NotificationPreferences.default
        preferences.pauseOnLowPowerMode = false
        preferences.pauseOnExpensiveNetwork = false
        preferences.scheduledSyncManuallyPaused = true
        fixture.controller.updateNotificationPreferences(preferences)

        fixture.controller.catchUpMissedScheduledRuns(now: now.addingTimeInterval(3_600))

        #expect(fixture.operations.inProgressSyncIDs.isEmpty)
        #expect(fixture.controller.pauseReason == .manual)
        #expect(fixture.controller.menuBarStatusLine == .paused(.manual))
    }

    @Test func verificationPreferenceOwnsItsIndependentTimer() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.controller.updateVerificationPreferences(
            VerificationPreferences(frequency: .day1, sampleSize: 2)
        )
        #expect(fixture.controller.nextVerificationFireDate() != nil)

        fixture.controller.updateVerificationPreferences(
            VerificationPreferences(frequency: .manual, sampleSize: 2)
        )
        #expect(fixture.controller.nextVerificationFireDate() == nil)
    }
}
