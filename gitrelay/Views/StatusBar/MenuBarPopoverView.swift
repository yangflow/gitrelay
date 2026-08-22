import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""

    private var filteredRepos: [RepoConfig] {
        MenuBarPopoverFilter.filteredRepos(
            appVM.repos,
            searchText: searchText,
            statuses: appVM.statuses
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: DesignTokens.Layout.popoverWidth)
        .onReceive(NotificationCenter.default.publisher(for: .gitrelayOpenMainWindow)) { _ in
            openMainWindow()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                Button(action: { openMainWindow() }) {
                    Text(verbatim: "GitRelay")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Open Main Window"))

                Spacer(minLength: DesignTokens.Spacing.xs)

                if !appVM.repos.isEmpty {
                    Button(String(localized: "Sync All")) { appVM.triggerSyncAll() }
                        .buttonStyle(QuietPressButtonStyle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button { openMainWindow(showing: .settings) } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Settings"))
                .accessibilityLabel(String(localized: "Settings"))
            }

            searchField

            if let line = appVM.menuBarStatusLine {
                MenuBarStatusLineView(line: line)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
        .padding(.vertical, DesignTokens.Spacing.popoverChromeVertical)
    }

    private var searchField: some View {
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

    @ViewBuilder
    private var content: some View {
        if appVM.repos.isEmpty {
            quietLine(String(localized: "No Repositories"))
        } else {
            SyncHealthSummaryView(summary: appVM.healthSummary)
                .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
                .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            if filteredRepos.isEmpty {
                quietLine(String(localized: "No Matching Repositories"))
            } else {
                repoList
            }
        }
    }

    private var repoList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredRepos) { repo in
                    MenuBarRepoRowView(
                        repo: repo,
                        status: appVM.statuses[repo.id] ?? .unknown,
                        syncPhase: appVM.syncPhases[repo.id],
                        recentRecords: appVM.records[repo.id] ?? [],
                        onOpen: { openMainWindow(focusing: repo.id) },
                        onSync: { appVM.triggerSync(repoID: repo.id) },
                        onReenterCredentials: {
                            appVM.requestReenterCredentials(repoID: repo.id)
                            openMainWindow(focusing: repo.id)
                        },
                        onOpenLog: {
                            appVM.requestOpenSyncLog(repoID: repo.id)
                            openMainWindow(focusing: repo.id)
                        }
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

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button(action: openAbout) {
                Image(systemName: "info.circle")
            }
            .help(String(localized: "About GitRelay"))
            .accessibilityLabel(String(localized: "About GitRelay"))

            Spacer(minLength: 0)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .help(String(localized: "Quit GitRelay"))
            .accessibilityLabel(String(localized: "Quit GitRelay"))
        }
        .buttonStyle(QuietPressButtonStyle())
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
        .padding(.vertical, DesignTokens.Spacing.popoverChromeVertical)
    }

    /// Empty and no-match states are one quiet line, not a centered slogan block.
    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
            .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func openMainWindow(
        focusing repoID: UUID? = nil,
        showing item: MainSidebarItem? = nil
    ) {
        appVM.pendingMainWindowRepoID = repoID
        appVM.pendingMainWindowSidebarItem = item
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
