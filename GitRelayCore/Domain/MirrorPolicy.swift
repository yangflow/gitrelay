import Foundation

nonisolated struct MirrorContentPolicy: Codable, Equatable, Sendable {
    static let completeRefSpecs = [
        "+refs/heads/*:refs/heads/*",
        "+refs/tags/*:refs/tags/*"
    ]

    var lfsMode: LFSMirrorMode
    var mirrorsReleases: Bool
    var depth: Int?
    var refSpecs: [String]

    init(
        lfsMode: LFSMirrorMode = .auto,
        mirrorsReleases: Bool = false,
        depth: Int? = nil,
        refSpecs: [String] = MirrorContentPolicy.completeRefSpecs
    ) {
        self.lfsMode = lfsMode
        self.mirrorsReleases = mirrorsReleases
        self.depth = depth.flatMap { $0 > 0 ? $0 : nil }
        let normalized = Self.normalizedRefSpecs(refSpecs)
        self.refSpecs = normalized.isEmpty ? Self.completeRefSpecs : normalized
    }

    var isCompleteMirror: Bool {
        depth == nil && refSpecs == Self.completeRefSpecs
    }

    static func normalizedRefSpecs(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated struct MirrorTriggerPolicy: Codable, Equatable, Sendable {
    var webhookEnabled: Bool

    init(webhookEnabled: Bool = false) {
        self.webhookEnabled = webhookEnabled
    }
}

nonisolated struct MirrorVerificationPolicy: Codable, Equatable, Sendable {
    var frequency: VerificationFrequency
    var branch: String

    init(frequency: VerificationFrequency = .manual, branch: String = "main") {
        self.frequency = frequency
        let normalized = branch
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "")
        self.branch = normalized.isEmpty ? "main" : normalized
    }
}

nonisolated struct MirrorPolicy: Codable, Equatable, Sendable {
    var frequency: SyncFrequency
    var destructivePush: DestructivePushPolicy
    var content: MirrorContentPolicy
    var triggers: MirrorTriggerPolicy
    var verification: MirrorVerificationPolicy

    init(
        frequency: SyncFrequency = .manual,
        destructivePush: DestructivePushPolicy = .strict,
        content: MirrorContentPolicy = MirrorContentPolicy(),
        triggers: MirrorTriggerPolicy = MirrorTriggerPolicy(),
        verification: MirrorVerificationPolicy = MirrorVerificationPolicy()
    ) {
        self.frequency = frequency
        self.destructivePush = destructivePush
        self.content = content
        self.triggers = triggers
        self.verification = verification
    }
}
