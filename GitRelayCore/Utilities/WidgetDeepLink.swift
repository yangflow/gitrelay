import Foundation

enum WidgetDeepLink {
    static let scheme = "gitrelay"

    static func openAppURL() -> URL {
        URL(string: "\(scheme)://open")!
    }

    static func repoURL(id: UUID) -> URL {
        URL(string: "\(scheme)://repo/\(id.uuidString.lowercased())")!
    }

    static func repoID(from url: URL) -> UUID? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else {
            return nil
        }

        switch url.host?.lowercased() {
        case "repo":
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard let rawID = pathComponents.first else { return nil }
            return UUID(uuidString: rawID)
        default:
            return nil
        }
    }
}

enum WidgetConstants {
    static let syncHealthWidgetKind = "SyncHealthWidget"
}
