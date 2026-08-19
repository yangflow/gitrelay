import SwiftUI

struct MenuBarRepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSync: () -> Void

    @State private var isHovered = false

    private var presentation: RepoRowHealthPresentation.Caption {
        RepoRowHealthPresentation.caption(for: repo, status: status)
    }

    var body: some View {
        Button(action: onSync) {
            HStack(spacing: 8) {
                StatusIconView(status: status)
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .foregroundStyle(isEscalatedFailure ? .red : .primary)
                        .lineLimit(1)
                    RepoRowCaptionView(caption: presentation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isEscalatedFailure, let count = RepoRowHealthPresentation.failureBadgeCount(for: repo) {
                    FailureCountBadge(count: count)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                    : Color.clear
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var isEscalatedFailure: Bool {
        RepoRowHealthPresentation.showsFailureBadge(for: repo)
    }
}
