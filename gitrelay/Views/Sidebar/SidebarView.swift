import SwiftUI

enum SidebarDisplayMode: String, CaseIterable, Identifiable {
    case all = "All"
    case byTag = "Group by Tag"

    var id: String { rawValue }
}

private struct TagGroupSheetItem: Identifiable {
    let tag: String?
    var id: String { tag ?? "__untagged__" }
}

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selectedRepoID: UUID?
    @Binding var sheetMode: SheetMode?

    @State private var displayMode: SidebarDisplayMode = .all
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteAlert = false
    @State private var batchFrequencyGroup: TagGroupSheetItem?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Display", selection: $displayMode) {
                ForEach(SidebarDisplayMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $selectedRepoID) {
                switch displayMode {
                case .all:
                    allReposList
                case .byTag:
                    groupedReposList
                }
            }
            .listStyle(.sidebar)

            if let pauseReason = appVM.scheduledSyncPauseReason {
                Divider()
                Label(pauseReason.displayMessage, systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !appVM.repos.isEmpty {
                Divider()
                SyncHealthSummaryView(summary: appVM.healthSummary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Manually", systemImage: "plus") { sheetMode = .add }
                    .help("Add a Repository Manually")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Browse Remote Repositories", systemImage: "magnifyingglass") { sheetMode = .browse }
                    .help("Browse and select from GitHub or GitLab")
            }
            ToolbarItem(placement: .automatic) {
                Button("Sync All", systemImage: "arrow.triangle.2.circlepath") {
                    appVM.triggerSyncAll()
                }
                .disabled(appVM.repos.isEmpty)
            }
            if displayMode == .byTag {
                ToolbarItem(placement: .automatic) {
                    tagGroupToolbarMenu
                }
            }
        }
        .sheet(item: $batchFrequencyGroup) { group in
            EditTagGroupFrequencySheet(
                tag: group.tag,
                repoCount: appVM.repos(matchingTag: group.tag).count
            )
        }
        .alert("Delete Repository", isPresented: $showDeleteAlert, presenting: pendingDeleteID) { id in
            Button("Delete", role: .destructive) {
                if selectedRepoID == id { selectedRepoID = nil }
                appVM.deleteRepo(id: id)
            }
            Button("Cancel", role: .cancel) { }
        } message: { id in
            let name = appVM.repos.first(where: { $0.id == id })?.name ?? ""
            Text("Delete “\(name)”? The local mirror cache will also be deleted. This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var allReposList: some View {
        ForEach(appVM.repos) { repo in
            repoRow(repo)
        }
    }

    @ViewBuilder
    private var groupedReposList: some View {
        let sections = RepoTagGrouping.sections(from: appVM.repos)
        if sections.isEmpty {
            ContentUnavailableView("No Repositories", systemImage: "folder")
        } else {
            ForEach(sections) { section in
                Section {
                    ForEach(section.repos) { repo in
                        repoRow(repo)
                    }
                } header: {
                    tagSectionHeader(section)
                }
            }
        }
    }

    private func tagSectionHeader(_ section: RepoTagGrouping.Section) -> some View {
        HStack(spacing: 6) {
            if section.tag != nil {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(section.title)
            Spacer()
            Text("\(section.repos.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            tagGroupContextMenu(tag: section.tag, repoCount: section.repos.count)
        }
    }

    @ViewBuilder
    private func tagGroupContextMenu(tag: String?, repoCount: Int) -> some View {
        Button("Sync This Group") {
            appVM.triggerSync(matchingTag: tag)
        }
        .disabled(repoCount == 0)

        Button("Verify This Group") {
            appVM.triggerVerify(matchingTag: tag)
        }
        .disabled(repoCount == 0)

        Divider()

        Button("Edit Frequency for All Repositories in Group...") {
            batchFrequencyGroup = TagGroupSheetItem(tag: tag)
        }
        .disabled(repoCount == 0)
    }

    private var tagGroupToolbarMenu: some View {
        Menu("Group Actions", systemImage: "tag") {
            ForEach(RepoTagGrouping.sections(from: appVM.repos)) { section in
                Menu("\(section.title) (\(section.repos.count))") {
                    tagGroupContextMenu(tag: section.tag, repoCount: section.repos.count)
                }
            }
        }
        .disabled(appVM.repos.isEmpty)
    }

    private func repoRow(_ repo: RepoConfig) -> some View {
        let status = appVM.statuses[repo.id] ?? .unknown
        return RepoRowView(
            repo: repo,
            status: status,
            onSyncNow: { appVM.triggerSync(repoID: repo.id) },
            onVerifyNow: { appVM.triggerVerify(repoID: repo.id) },
            onEdit: { sheetMode = .edit(repo) },
            onDelete: {
                pendingDeleteID = repo.id
                showDeleteAlert = true
            }
        )
        .tag(repo.id)
    }
}
