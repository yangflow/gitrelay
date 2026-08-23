import Foundation
import Testing
@testable import GitRelay

struct MirrorDetailPresentationTests {
    @Test(arguments: [
        (MirrorActivityState.queued(position: 2), MirrorPrimaryAction.cancelQueuedRun),
        (.synchronizing(phase: SyncPhase(.fetchingSource), progress: nil), .cancelSync),
        (.verifying(progress: nil), .cancelVerification)
    ])
    func activeWorkOwnsThePrimaryAction(
        activity: MirrorActivityState,
        expected: MirrorPrimaryAction
    ) {
        let mirror = MirrorSnapshot(name: "mirror", srcURL: source, dstURL: target)
        #expect(MirrorDetailPresentation.make(mirror: mirror, activity: activity).primaryAction == expected)
    }

    @Test func neverRunStartsFirstSync() {
        let mirror = MirrorSnapshot(name: "mirror", srcURL: source, dstURL: target)
        #expect(MirrorDetailPresentation.make(mirror: mirror, activity: .idle).primaryAction == .startFirstSync)
    }

    @Test func pausedMirrorResumesBeforeStartingWork() {
        let mirror = MirrorSnapshot(
            name: "mirror",
            srcURL: source,
            dstURL: target,
            scheduledSyncPaused: true
        )
        #expect(MirrorDetailPresentation.make(mirror: mirror, activity: .idle).primaryAction == .resumeSchedule)
    }

    @Test func failuresMapToTargetedRepairActions() {
        let destinationID = UUID()
        var mirror = MirrorSnapshot(
            name: "mirror",
            srcURL: source,
            targets: [MirrorTarget(id: destinationID, url: target)]
        )
        mirror.health.lastFailure = MirrorFailureSummary(
            kind: .destinationAuthentication,
            message: "denied",
            destinationID: destinationID
        )
        mirror.needsCredentials = true
        #expect(
            MirrorDetailPresentation.make(mirror: mirror, activity: .idle).primaryAction
                == .reconnectCredential(destinationID: destinationID)
        )

        mirror.needsCredentials = false
        mirror.health.lastFailure = MirrorFailureSummary(
            kind: .destructiveChangeBlocked,
            message: "blocked"
        )
        #expect(MirrorDetailPresentation.make(mirror: mirror, activity: .idle).primaryAction == .reviewChanges)
    }

    private var source: String { "git@github.com:acme/source.git" }
    private var target: String { "git@gitlab.com:acme/target.git" }
}
