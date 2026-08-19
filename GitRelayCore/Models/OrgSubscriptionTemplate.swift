import Foundation

/// Preset mirror settings applied when auto-adding repos discovered via org subscription.
struct OrgSubscriptionTemplate: Codable, Equatable, Hashable, Sendable {
    var sourceAuthMode: AuthMode
    var sourceKeyPath: String
    var targetURLTemplate: String
    var targetAuthMode: AuthMode
    var targetKeyPath: String
    var namePrefix: String
    var frequency: SyncFrequency
    var targetAutoCreate: Bool
    var targetCreateHost: String
    var targetNamespaceKind: OrgSubscriptionTargetNamespaceKind
    var targetNamespaceOwner: String
    var targetVisibilityPrivate: Bool

    static let `default` = OrgSubscriptionTemplate(
        sourceAuthMode: .sshAgent,
        sourceKeyPath: "",
        targetURLTemplate: "",
        targetAuthMode: .sshAgent,
        targetKeyPath: "",
        namePrefix: "",
        frequency: .manual,
        targetAutoCreate: false,
        targetCreateHost: "",
        targetNamespaceKind: .currentUser,
        targetNamespaceOwner: "",
        targetVisibilityPrivate: true
    )
}

enum OrgSubscriptionTargetNamespaceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case currentUser, organization, adminForUser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentUser:  String(localized: "Current User")
        case .organization: String(localized: "Organization")
        case .adminForUser: String(localized: "Administrator Creates for User")
        }
    }
}
