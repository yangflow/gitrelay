import SwiftUI
import AppKit

// MARK: - Menu bar icon (label for MenuBarExtra)

struct MenuBarIconLabel: View {
    let appVM: AppViewModel

    var body: some View {
        Image(nsImage: icon)
    }

    private var icon: NSImage {
        let hasFailed = appVM.statuses.values.contains { if case .failed = $0 { return true }; return false }
        let name = hasFailed ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "GitRelay")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }
}

// MARK: - Popover root

struct MenuBarPopoverView: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("全部同步") { appVM.triggerSyncAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer()
                Button("打开主窗口") { openMainWindow() }
                    .controlSize(.small)
                Button {
                    openWindow(id: "about")
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("关于 GitRelay")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if appVM.repos.isEmpty {
                Text("暂无仓库")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appVM.repos) { repo in
                            MenuBarRepoRow(
                                repo: repo,
                                status: appVM.statuses[repo.id] ?? .unknown,
                                onSync: { appVM.triggerSync(repoID: repo.id) }
                            )
                            if repo.id != appVM.repos.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 280)
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Repo row

struct MenuBarRepoRow: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSync: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSync) {
            HStack(spacing: 8) {
                StatusIconView(status: status)
                    .frame(width: 18, alignment: .center)
                Text(repo.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let date = repo.lastSyncedAt {
                        Text(date.relativeFormatted)
                    } else {
                        Text("未同步")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
