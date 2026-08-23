import Foundation

nonisolated enum AttentionSeverity: Int, Codable, Comparable, Sendable {
    case information
    case warning
    case critical

    static func < (lhs: AttentionSeverity, rhs: AttentionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
nonisolated enum AttentionAction: Codable, Equatable, Hashable, Sendable {
    case completeSetup
    case startFirstSync
    case reconnectSource
    case reconnectDestination(UUID)
    case reviewDestructiveChange
    case reviewDivergence
    case retry
    case resumeSchedule
}

nonisolated struct AttentionItem: Identifiable, Equatable, Hashable, Sendable {
    var mirrorID: UUID
    var destinationID: UUID?
    var severity: AttentionSeverity
    var title: String
    var message: String
    var action: AttentionAction

    var id: String {
        [mirrorID.uuidString, destinationID?.uuidString, String(describing: action)]
            .compactMap { $0 }
            .joined(separator: ":")
    }
}
