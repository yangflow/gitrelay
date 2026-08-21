import SwiftUI

struct RepoRowCaptionView: View {
    let caption: RepoRowHealthPresentation.Caption

    var body: some View {
        Text(captionText)
            .font(.caption2)
            .foregroundStyle(caption.isStale ? .tertiary : .secondary)
            .lineLimit(1)
    }

    private var captionText: String {
        switch caption.kind {
        case .needsCredentials:
            return String(localized: "Needs credentials")
        case .diverged:
            return String(localized: "Content divergence")
        case .neverSynced:
            return String(localized: "Not Synced")
        case .lastSync(let date):
            let relative = date.formatted(.relative(presentation: .named))
            return String(localized: "Last synced \(relative)")
        case .queued:
            return String(localized: "Queued")
        case .syncing(let text):
            return text
        }
    }
}
