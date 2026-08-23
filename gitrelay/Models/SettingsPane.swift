import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case connections
    case defaultPolicies
    case notifications
    case integrations
    case storageMaintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            String.loc("General")
        case .connections:
            String.loc("Connections")
        case .defaultPolicies:
            String.loc("Default Policies")
        case .notifications:
            String.loc("Notifications")
        case .integrations:
            String.loc("Integrations")
        case .storageMaintenance:
            String.loc("Storage & Maintenance")
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .connections:
            "link"
        case .defaultPolicies:
            "slider.horizontal.3"
        case .notifications:
            "bell"
        case .integrations:
            "point.3.connected.trianglepath.dotted"
        case .storageMaintenance:
            "internaldrive"
        }
    }

}
