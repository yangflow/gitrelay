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
            return String.loc("Needs credentials")
        case .diverged:
            return String.loc("Content divergence")
        case .neverSynced:
            return String.loc("Not Synced")
        case .lastSync(let date):
            let relative = date.formatted(.relative(presentation: .named))
            return String.loc("Last synced \(relative)")
        case .queued:
            return String.loc("Queued")
        case .syncing(let text):
            return text
        }
    }
}
