import Foundation
import Testing
@testable import GitRelay

@Suite("Mirror list projection")
struct MirrorListProjectionTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func mirror(
        name: String,
        targets: [MirrorTarget]? = nil,
        lastSuccess: Date? = nil,
        error: String? = nil,
        needsCredentials: Bool = false,
        labels: [String] = []
    ) -> MirrorSnapshot {
        MirrorSnapshot(
            name: name,
            srcURL: "git@github.com:acme/\(name).git",
            targets: targets ?? [MirrorTarget(url: "git@gitlab.com:acme/\(name).git")],
            lastSyncedAt: error == nil ? lastSuccess : now,
            lastSuccessfulSyncedAt: lastSuccess,
            lastSyncError: error,
            tags: labels,
            needsCredentials: needsCredentials
        )
    }

    @Test func projectionKeepsHealthIndependentFromLiveActivity() {
        let failed = mirror(
            name: "billing",
            lastSuccess: now.addingTimeInterval(-600),
            error: "destination rejected"
        )
        let phase = SyncPhase(.pushingTarget("backup"))

        let row = MirrorListProjection.row(
            for: failed,
            activity: .synchronizing(phase: phase, progress: nil),
            schedule: .active(nextRunAt: now.addingTimeInterval(900)),
            now: now
        )

        #expect(row.health == .failed)
        #expect(row.healthDetail == "destination rejected")
        #expect(row.activity == .synchronizing(phase))
    }

    @Test func credentialsAndStalenessAreVisibleWithoutRuntimeStatusFlattening() {
        let credentials = mirror(name: "private", needsCredentials: true)
        let stale = mirror(
            name: "archive",
            lastSuccess: now.addingTimeInterval(-MirrorListProjection.staleInterval - 1)
        )

        #expect(
            MirrorListProjection.row(
                for: credentials,
                activity: .idle,
                schedule: .active(nextRunAt: nil),
                now: now
            ).health == .needsCredentials
        )
        #expect(
            MirrorListProjection.row(
                for: stale,
                activity: .idle,
                schedule: .active(nextRunAt: nil),
                now: now
            ).health == .stale
        )
    }

    @Test func destinationFiltersAndSearchCoverRoutesAndLabels() {
        let multi = mirror(
            name: "production",
            targets: [
                MirrorTarget(url: "git@gitlab.com:acme/primary.git"),
                MirrorTarget(
                    kind: .filesystem,
                    filesystemPath: "/Volumes/Archive/production"
                ),
            ],
            labels: ["critical"]
        )
        let row = MirrorListProjection.row(
            for: multi,
            activity: .idle,
            schedule: .active(nextRunAt: nil),
            now: now
        )

        #expect(MirrorListProjection.filter([row], searchText: "critical", filter: .all) == [row])
        #expect(MirrorListProjection.filter([row], searchText: "archive", filter: .all) == [row])
        #expect(MirrorListProjection.filter([row], searchText: "", filter: .gitDestinations) == [row])
        #expect(MirrorListProjection.filter([row], searchText: "", filter: .archiveDestinations) == [row])
        #expect(MirrorListProjection.filter([row], searchText: "", filter: .multipleDestinations) == [row])
    }

    @Test func priorityAndDateSortsAreStableAtTwoHundredMirrors() {
        let mirrors = (0..<200).map { index in
            mirror(
                name: String(format: "mirror-%03d", 199 - index),
                lastSuccess: now.addingTimeInterval(TimeInterval(-index))
            )
        }
        let rows = mirrors.map {
            MirrorListProjection.row(
                for: $0,
                activity: .idle,
                schedule: .active(nextRunAt: now.addingTimeInterval(3_600)),
                now: now
            )
        }

        let named = MirrorListProjection.sort(rows, order: .name)
        let recent = MirrorListProjection.sort(rows, order: .lastSuccess)

        #expect(named.count == 200)
        #expect(named.first?.name == "mirror-000")
        #expect(recent.first?.lastSuccessfulAt == now)
    }
}
