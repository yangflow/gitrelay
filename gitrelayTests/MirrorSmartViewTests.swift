import Foundation
import Testing
@testable import GitRelay

@Suite("Mirror smart views")
struct MirrorSmartViewTests {
    private func context(
        labels: [String] = [],
        health: MirrorHealthState = .healthy,
        activity: MirrorActivityState = .idle,
        schedule: MirrorScheduleState = .active(nextRunAt: nil),
        needsCredentials: Bool = false
    ) -> MirrorSmartViewContext {
        MirrorSmartViewContext(
            mirrorID: UUID(),
            labels: labels,
            health: health,
            activity: activity,
            schedule: schedule,
            needsCredentials: needsCredentials
        )
    }

    @Test func primaryMembershipKeepsHealthActivityAndScheduleIndependent() {
        let failure = MirrorFailureSummary(
            kind: .unknown,
            message: "failed",
            failedAt: Date()
        )
        let contexts = [
            context(health: .failed(failure)),
            context(activity: .queued(position: 1)),
            context(activity: .verifying(progress: nil)),
            context(schedule: .mirrorPaused),
            context(schedule: .deferred(.quietHours)),
            context(needsCredentials: true),
            context(),
        ]

        #expect(MirrorSmartViewQuery.count(for: .allMirrors, in: contexts) == 7)
        #expect(MirrorSmartViewQuery.count(for: .needsAttention, in: contexts) == 2)
        #expect(MirrorSmartViewQuery.count(for: .running, in: contexts) == 2)
        #expect(MirrorSmartViewQuery.count(for: .paused, in: contexts) == 2)
    }

    @Test func labelsAreDerivedDeduplicatedAndSorted() {
        let contexts = [
            context(labels: ["Production", " personal "]),
            context(labels: ["production", "Archive", ""]),
        ]

        #expect(MirrorSmartViewQuery.labels(in: contexts) == ["Archive", "personal", "Production"])
        #expect(
            MirrorSmartViewQuery.availableViews(in: contexts) == [
                .needsAttention,
                .allMirrors,
                .running,
                .paused,
                .label("Archive"),
                .label("personal"),
                .label("Production"),
            ]
        )
        #expect(MirrorSmartViewQuery.count(for: .label("PRODUCTION"), in: contexts) == 2)
    }

    @Test func defaultAndReconciliationPreferActionableWork() {
        let healthy = [context()]
        #expect(MirrorSmartViewQuery.defaultSelection(in: healthy) == .allMirrors)

        let actionable = [context(health: .neverRun)]
        #expect(MirrorSmartViewQuery.defaultSelection(in: actionable) == .needsAttention)
        #expect(
            MirrorSmartViewQuery.reconciledSelection(.label("missing"), in: actionable)
                == .needsAttention
        )
    }

    @Test func identifiersRoundTripWithoutPersistingDerivedMembership() {
        let values: [MirrorSmartView] = [
            .needsAttention,
            .allMirrors,
            .running,
            .paused,
            .label("production"),
        ]
        for value in values {
            #expect(MirrorSmartView(id: value.id) == value)
        }
        #expect(MirrorSmartView(id: "label:") == nil)
        #expect(MirrorSmartView(id: "unknown") == nil)
    }
}
