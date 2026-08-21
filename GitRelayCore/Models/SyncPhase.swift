import Foundation

/// High-level stage of an in-flight sync, shown in detail / sidebar / menu bar.
/// Optional `progressDetail` is a **parsed** objects/bytes summary — never raw git stderr.
nonisolated struct SyncPhase: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case cloningSource
        case fetchingSource
        case fetchingLFS
        case pushingTarget(String)
        case pushingLFS(String)
        case archivingTarget(String)
    }

    var kind: Kind
    /// Safe, user-facing progress such as `"1,234 / 2,745 objects"` or `"12.5 MiB"`.
    var progressDetail: String?

    init(_ kind: Kind, progressDetail: String? = nil) {
        self.kind = kind
        self.progressDetail = progressDetail
    }

    func withProgress(_ detail: String?) -> SyncPhase {
        SyncPhase(kind, progressDetail: detail)
    }

    var statusTitle: String {
        switch kind {
        case .cloningSource:
            return String(localized: "Cloning...")
        case .fetchingSource:
            return String(localized: "Fetching...")
        case .fetchingLFS:
            return String(localized: "Fetching LFS...")
        case .pushingTarget:
            return String(localized: "Pushing...")
        case .pushingLFS:
            return String(localized: "Pushing LFS...")
        case .archivingTarget:
            return String(localized: "Archiving...")
        }
    }

    /// Single-line caption for sidebar and menu bar rows.
    var displayCaption: String {
        if let progressDetail, !progressDetail.isEmpty {
            return "\(statusTitle) · \(progressDetail)"
        }
        return statusTitle
    }
}
