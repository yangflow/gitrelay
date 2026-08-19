import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""

    private var filteredRepos: [RepoConfig] {
        MenuBarPopoverFilter.filteredRepos(appVM.repos, searchText: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button("Sync All") { appVM.triggerSyncAll() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(appVM.repos.isEmpty)
                    Spacer()
                    Button("Open Main Window", action: { openMainWindow(focusing: nil) })
                        .controlSize(.small)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search Repositories", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let pauseReason = appVM.scheduledSyncPauseReason {
                Divider()
                Label(pauseReason.displayMessage, systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if appVM.repos.isEmpty {
                Text("No Repositories")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                SyncHealthSummaryView(summary: appVM.healthSummary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                if filteredRepos.isEmpty {
                    Text("No Matching Repositories")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredRepos) { repo in
                                MenuBarRepoRowView(
                                    repo: repo,
                                    status: appVM.statuses[repo.id] ?? .unknown,
                                    onOpen: { openMainWindow(focusing: repo.id) },
                                    onSync: { appVM.triggerSync(repoID: repo.id) }
                                )
                                if repo.id != filteredRepos.last?.id {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }

            Divider()

            HStack(spacing: 20) {
                Button(action: openAbout) {
                    Image(systemName: "info.circle")
                }
                .help("About GitRelay")

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .keyboardShortcut("q")
                .help("Quit GitRelay")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .onReceive(NotificationCenter.default.publisher(for: .gitrelayOpenMainWindow)) { _ in
            openMainWindow(focusing: nil)
        }
    }

    private func openMainWindow(focusing repoID: UUID?) {
        appVM.pendingMainWindowRepoID = repoID
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
