import Foundation

nonisolated struct DestructivePushPlan: Equatable, Sendable {
    var deletedRefs: [String]
    var forcedUpdateRefs: [String]
    /// Commits the destination's branches hold that no source branch reaches.
    /// Nil when git could not be asked, so the sheet drops the number rather
    /// than claiming zero.
    var destinationOnlyCommits: Int?

    var isDestructive: Bool {
        !deletedRefs.isEmpty || !forcedUpdateRefs.isEmpty
    }

    var summary: String {
        String.loc("\(deletedRefs.count) deletions, \(forcedUpdateRefs.count) forced updates")
    }

    static let empty = DestructivePushPlan(deletedRefs: [], forcedUpdateRefs: [])

    func withDestinationOnlyCommits(_ count: Int?) -> DestructivePushPlan {
        var updated = self
        updated.destinationOnlyCommits = count
        return updated
    }

    nonisolated static func parse(gitOutput: String) -> DestructivePushPlan {
        var deletedRefs: [String] = []
        var forcedUpdateRefs: [String] = []

        for line in gitOutput.split(whereSeparator: \.isNewline).map(String.init) {
            if line.contains("[deleted]"), let ref = refNameAfterMarker("[deleted]", in: line) {
                deletedRefs.append(ref)
            }

            if line.contains("(forced update)"), let ref = refNameBeforeForcedUpdate(in: line) {
                forcedUpdateRefs.append(ref)
            }
        }

        return DestructivePushPlan(
            deletedRefs: deletedRefs,
            forcedUpdateRefs: forcedUpdateRefs
        )
    }

    nonisolated private static func refNameAfterMarker(_ marker: String, in line: String) -> String? {
        guard let markerRange = line.range(of: marker) else { return nil }
        let tail = line[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.split(separator: " ").last.map(String.init)
    }

    nonisolated private static func refNameBeforeForcedUpdate(in line: String) -> String? {
        guard let reasonRange = line.range(of: "(forced update)") else { return nil }
        let update = line[..<reasonRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let arrowRange = update.range(of: " -> ", options: .backwards) {
            let destination = update[arrowRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return destination.isEmpty ? nil : destination
        }

        return update.split(separator: " ").last.map(String.init)
    }
}
