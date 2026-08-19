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
        case .diverged:
            return "Content divergence"
        case .neverSynced:
            return "Not Synced"
        case .lastSync(let date):
            let relative = date.formatted(.relative(presentation: .named))
            return "Last synced \(relative)"
        }
    }
}
