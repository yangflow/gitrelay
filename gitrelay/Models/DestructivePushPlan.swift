import Foundation

struct DestructivePushPlan: Equatable {
    var deletedRefs: [String]
    var forcedUpdateRefs: [String]

    var isDestructive: Bool {
        !deletedRefs.isEmpty || !forcedUpdateRefs.isEmpty
    }

    var summary: String {
        "\(deletedRefs.count) 个删除, \(forcedUpdateRefs.count) 个强制更新"
    }

    static let empty = DestructivePushPlan(deletedRefs: [], forcedUpdateRefs: [])

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
