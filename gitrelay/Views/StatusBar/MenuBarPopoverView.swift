import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("全部同步") { appVM.triggerSyncAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer()
                Button("打开主窗口", action: openMainWindow)
                    .controlSize(.small)
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
                SyncHealthSummaryView(summary: appVM.healthSummary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appVM.repos) { repo in
                            MenuBarRepoRowView(
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

            Divider()

            HStack(spacing: 20) {
                Button(action: openAbout) {
                    Image(systemName: "info.circle")
                }
                .help("关于 GitRelay")

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .keyboardShortcut("q")
                .help("退出 GitRelay")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .onReceive(NotificationCenter.default.publisher(for: .gitrelayOpenMainWindow)) { _ in
            openMainWindow()
        }
    }

    private func openMainWindow() {
        let popover = NSApp.keyWindow
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        popover?.close()
    }

    private func openAbout() {
        let popover = NSApp.keyWindow
        openWindow(id: "about")
        popover?.close()
    }
}
