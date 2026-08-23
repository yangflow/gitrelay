import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(MirrorLibraryModel.self) private var library
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorSchedulingController.self) private var scheduling
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""

    private var filteredRepos: [MirrorSnapshot] {
        MenuBarPopoverFilter.filteredRepos(
            library.mirrors,
            searchText: searchText,
            statuses: operations.statuses
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
                .help(String.loc("Open Main Window"))

                Spacer(minLength: DesignTokens.Spacing.xs)

                if !library.mirrors.isEmpty {
                    Button(String.loc("Sync All")) { operations.triggerSyncAll() }
                        .buttonStyle(QuietPressButtonStyle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button { showSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(String.loc("Settings"))
                .accessibilityLabel(String.loc("Settings"))
            }

            searchField

            if let line = scheduling.menuBarStatusLine {
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
            TextField("Search Mirrors", text: $searchText)
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
        if library.mirrors.isEmpty {
            quietLine(String.loc("No Mirrors"))
        } else {
            SyncHealthSummaryView(
                summary: SyncHealthSummary.make(
                    repos: library.mirrors,
                    statuses: operations.statuses
                )
            )
                .padding(.horizontal, DesignTokens.Spacing.popoverChromeHorizontal)
                .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            if filteredRepos.isEmpty {
                quietLine(String.loc("No Matching Mirrors"))
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
                        status: operations.statuses[repo.id] ?? .unknown,
                        syncPhase: operations.syncPhases[repo.id],
                        recentRecords: operations.records[repo.id] ?? [],
                        onOpen: { openMainWindow(focusing: repo.id) },
                        onSync: { operations.triggerSync(mirrorID: repo.id) },
                        onReenterCredentials: {
                            workspace.requestEditCredentials(mirrorID: repo.id)
                            openMainWindow(focusing: repo.id)
                        },
                        onOpenLog: {
                            workspace.requestOpenSyncLog(mirrorID: repo.id)
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
            .help(String.loc("About GitRelay"))
            .accessibilityLabel(String.loc("About GitRelay"))

            Spacer(minLength: 0)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .help(String.loc("Quit GitRelay"))
            .accessibilityLabel(String.loc("Quit GitRelay"))
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

    private func openMainWindow(focusing repoID: UUID? = nil) {
        workspace.requestMirrorSelection(repoID)
        let popover = NSApp.keyWindow
        NSApp.setActivationPolicy(.regular)
        if let mainWindow = NSApp.windows.first(where: { $0.title == "GitRelay" }) {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
        if popover !== NSApp.keyWindow {
            popover?.close()
        }
    }

    private func showSettings() {
        let popover = NSApp.keyWindow
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
        popover?.close()
    }

    private func openAbout() {
        let popover = NSApp.keyWindow
        popover?.close()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "about")
    }
}
