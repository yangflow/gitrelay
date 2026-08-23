import Foundation

/// Global defaults copied into newly created mirrors.
///
/// These values are never linked back to existing mirrors. Once a mirror is
/// created, its `MirrorPolicy` remains an explicit per-mirror configuration.
nonisolated struct MirrorDefaultPolicyPreferences: Codable, Equatable, Sendable {
    var frequency: SyncFrequency
    var destructivePush: DestructivePushPolicy
    var lfsMode: LFSMirrorMode
    var mirrorsReleases: Bool
    var webhookEnabled: Bool
    var verificationFrequency: VerificationFrequency

    init(
        frequency: SyncFrequency = .manual,
        destructivePush: DestructivePushPolicy = .strict,
        lfsMode: LFSMirrorMode = .auto,
        mirrorsReleases: Bool = false,
        webhookEnabled: Bool = false,
        verificationFrequency: VerificationFrequency = .manual
    ) {
        self.frequency = frequency
        self.destructivePush = destructivePush
        self.lfsMode = lfsMode
        self.mirrorsReleases = mirrorsReleases
        self.webhookEnabled = webhookEnabled
        self.verificationFrequency = verificationFrequency
    }

    static let `default` = MirrorDefaultPolicyPreferences()
}
