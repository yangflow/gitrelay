import Foundation
import Testing
@testable import GitRelay

@MainActor
@Suite(.serialized)
struct MirrorDefaultPolicyTests {
    @Test func storePersistsDefaultPolicy() {
        let suite = "gitrelay.default-policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MirrorDefaultPolicyStore(defaults: defaults)
        store.preferences = MirrorDefaultPolicyPreferences(
            frequency: .hour1,
            destructivePush: .auto,
            lfsMode: .off,
            mirrorsReleases: true,
            webhookEnabled: true,
            verificationFrequency: .week1
        )

        #expect(MirrorDefaultPolicyStore(defaults: defaults).preferences == store.preferences)
    }

    @Test func defaultsApplyOnlyToNewMirrors() {
        let policy = MirrorDefaultPolicyPreferences(
            frequency: .day1,
            destructivePush: .auto,
            lfsMode: .off,
            mirrorsReleases: true,
            webhookEnabled: true,
            verificationFrequency: .month1
        )
        let created = MirrorEditorModel(defaultPolicy: policy)

        #expect(created.frequency == .day1)
        #expect(created.destructivePushPolicy == .auto)
        #expect(created.lfsMirrorMode == .off)
        #expect(created.mirrorReleases)
        #expect(created.webhookEnabled)
        #expect(created.verificationFrequency == .month1)

        let existing = MirrorSnapshot(
            name: "Existing",
            srcURL: "git@github.com:acme/source.git",
            dstURL: "git@gitlab.com:acme/mirror.git",
            frequency: .min15,
            destructivePushPolicy: .strict,
            mirrorReleases: false,
            lfsMirrorMode: .auto,
            webhookEnabled: false,
            verificationFrequency: .week1
        )
        let edited = MirrorEditorModel(editing: existing, defaultPolicy: policy)

        #expect(edited.frequency == .min15)
        #expect(edited.destructivePushPolicy == .strict)
        #expect(edited.lfsMirrorMode == .auto)
        #expect(!edited.mirrorReleases)
        #expect(!edited.webhookEnabled)
        #expect(edited.verificationFrequency == .week1)
    }

    @Test func connectedServiceBatchUsesSameDefaults() {
        let suite = "gitrelay.connected-default-policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = MirrorDefaultPolicyPreferences(
            frequency: .hour1,
            destructivePush: .auto,
            lfsMode: .off,
            mirrorsReleases: true,
            webhookEnabled: true,
            verificationFrequency: .day1
        )

        let model = ConnectedServiceSourceModel(defaultPolicy: policy, defaults: defaults)
        #expect(model.frequency == .hour1)
        #expect(model.defaultPolicy == policy)
    }
}
