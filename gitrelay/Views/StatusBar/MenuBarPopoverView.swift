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
            VStack(spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Button("Sync All") { appVM.triggerSyncAll() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(appVM.repos.isEmpty)
                    Spacer()
                    Button("Open Main Window", action: { openMainWindow(focusing: nil) })
                        .controlSize(.small)
                }

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search Repositories", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(minHeight: DesignTokens.Size.searchFieldMinHeight)
                .background(DesignTokens.Surface.searchFieldFill)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.CornerRadius.control,
                        style: .continuous
                    )
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
            .padding(.vertical, DesignTokens.Spacing.popoverChromeVertical)

            if let pauseReason = appVM.scheduledSyncPauseReason {
                Divider()
                Label(pauseReason.displayMessage, systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.StatusColor.pause)
                    .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if appVM.repos.isEmpty {
                Text("No Repositories")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(DesignTokens.Spacing.xl)
            } else {
                SyncHealthSummaryView(summary: appVM.healthSummary)
                    .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
                    .padding(.vertical, DesignTokens.Spacing.sm)

                Divider()

                if filteredRepos.isEmpty {
                    Text("No Matching Repositories")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(DesignTokens.Spacing.xl)
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
                                    Divider()
                                        .padding(.leading, DesignTokens.Spacing.xxl + DesignTokens.Spacing.md)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: DesignTokens.Layout.popoverListMaxHeight)
                }
            }

            Divider()

            HStack(spacing: DesignTokens.Spacing.xl) {
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
            .padding(.horizontal, DesignTokens.Spacing.lg - DesignTokens.Spacing.xxxs)
            .padding(.vertical, DesignTokens.Spacing.popoverChromeVertical)
        }
        .frame(width: DesignTokens.Layout.popoverWidth)
        .gitRelayChrome(.popover)
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
