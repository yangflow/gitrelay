import Foundation

enum ArchiveFormat: String, Codable, CaseIterable, Identifiable {
    case tarGz
    case zip
    case gitBundle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tarGz: return "tar.gz"
        case .zip: return "zip"
        case .gitBundle: return "git bundle"
        }
    }

    var fileExtension: String {
        switch self {
        case .tarGz: return "tar.gz"
        case .zip: return "zip"
        case .gitBundle: return "bundle"
        }
    }

    var defaultFilenameTemplate: String {
        "{name}-{date}.\(fileExtension)"
    }
}
