import SwiftUI

struct MenuBarRepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onOpen: () -> Void
    let onSync: () -> Void

    @State private var isHovered = false

    private var presentation: RepoRowHealthPresentation.Caption {
        RepoRowHealthPresentation.caption(for: repo, status: status)
    }

    private var canSync: Bool {
        MenuBarPopoverFilter.canTriggerSync(for: status)
    }

    var body: some View {
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
            if isHovered {
                Button(action: onSync) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Sync Now")
                .disabled(!canSync)
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
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
    }

    private var isEscalatedFailure: Bool {
        RepoRowHealthPresentation.showsFailureBadge(for: repo)
    }
}
