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
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredRepos: [RepoConfig] {
        appVM.displayedSidebarRepos
    }

    private var isFilterActive: Bool {
        let trimmed = appVM.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || appVM.sidebarStatusFilter != .all
    }

    var body: some View {
        @Bindable var appVM = appVM
        VStack(spacing: 0) {
            sidebarSearchChrome(
                searchText: $appVM.sidebarSearchText,
                statusFilter: $appVM.sidebarStatusFilter
            )

            List(selection: $selectedRepoID) {
                switch displayMode {
                case .all:
                    allReposList
                case .byTag:
                    groupedReposList
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let pauseReason = appVM.scheduledSyncPauseReason {
                Divider()
                Label(pauseReason.displayMessage, systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.StatusColor.pause)
                    .padding(.horizontal, DesignTokens.Spacing.sidebarChromeHorizontal)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GitRelayVisualEffectView(
                            material: DesignTokens.Material.footer.nsMaterial,
                            blendingMode: DesignTokens.Material.footer.blendingMode
                        )
                    }
            }

            if !appVM.repos.isEmpty {
                Divider()
                SyncHealthSummaryView(summary: appVM.healthSummary)
                    .padding(.horizontal, DesignTokens.Spacing.sidebarChromeHorizontal)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background {
                        GitRelayVisualEffectView(
                            material: DesignTokens.Material.footer.nsMaterial,
                            blendingMode: DesignTokens.Material.footer.blendingMode
                        )
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
                Task { await confirmDelete(id: id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { id in
            let name = appVM.repos.first(where: { $0.id == id })?.name ?? ""
            Text("Delete “\(name)”? The local mirror cache will also be deleted. This action cannot be undone.")
        }
        .onAppear {
            applyPendingFocusSidebarSearch()
        }
        .onChange(of: appVM.pendingFocusSidebarSearch) { _, isPending in
            guard isPending else { return }
            applyPendingFocusSidebarSearch()
        }
    }

    private func applyPendingFocusSidebarSearch() {
        guard appVM.consumePendingFocusSidebarSearch() else { return }
        isSearchFieldFocused = true
    }

    private func sidebarSearchChrome(
        searchText: Binding<String>,
        statusFilter: Binding<SidebarRepoFilter.StatusFilter>
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search Repositories", text: searchText)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($isSearchFieldFocused)
            if !searchText.wrappedValue.isEmpty {
                Button {
                    searchText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }

            sidebarFilterMenu(statusFilter: statusFilter)
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
        .padding(.horizontal, DesignTokens.Spacing.sidebarChromeHorizontal)
        .padding(.vertical, DesignTokens.Spacing.sidebarChromeVertical)
    }

    private func sidebarFilterMenu(
        statusFilter: Binding<SidebarRepoFilter.StatusFilter>
    ) -> some View {
        Menu {
            Picker(String(localized: "Status Filter"), selection: statusFilter) {
                ForEach(SidebarRepoFilter.StatusFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.rawValue)).tag(filter)
                }
            }

            Divider()

            Picker(String(localized: "Display"), selection: $displayMode) {
                ForEach(SidebarDisplayMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
        } label: {
            Image(systemName: filterMenuSymbol)
                .font(.caption)
                .foregroundStyle(isFilterChromeActive ? Color.accentColor : Color.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help(String(localized: "Filter and Display"))
        .accessibilityLabel(String(localized: "Filter and Display"))
    }

    private var isFilterChromeActive: Bool {
        appVM.sidebarStatusFilter != .all || displayMode != .all
    }

    private var filterMenuSymbol: String {
        isFilterChromeActive
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    @ViewBuilder
    private var allReposList: some View {
        if filteredRepos.isEmpty {
            emptyListPlaceholder
        } else {
            ForEach(filteredRepos) { repo in
                repoRow(repo)
            }
        }
    }

    @ViewBuilder
    private var groupedReposList: some View {
        let sections = RepoTagGrouping.sections(from: filteredRepos)
        if sections.isEmpty {
            emptyListPlaceholder
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

    @ViewBuilder
    private var emptyListPlaceholder: some View {
        if appVM.repos.isEmpty {
            Text(String(localized: "No Repositories"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xl)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if isFilterActive {
            Text("No Matching Repositories")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xl)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func tagSectionHeader(_ section: RepoTagGrouping.Section) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
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

    private func confirmDelete(id: UUID) async {
        guard await appVM.authorizeSensitiveAction(.deleteRepository) else { return }
        if selectedRepoID == id { selectedRepoID = nil }
        appVM.deleteRepo(id: id)
    }

    private func repoRow(_ repo: RepoConfig) -> some View {
        let status = appVM.statuses[repo.id] ?? .unknown
        let isSelected = selectedRepoID == repo.id
        return RepoRowView(
            repo: repo,
            status: status,
            syncPhase: appVM.syncPhases[repo.id],
            recentRecords: appVM.records[repo.id] ?? [],
            onSyncNow: { appVM.triggerSync(repoID: repo.id) },
            onCancelSync: { appVM.cancelSync(repoID: repo.id) },
            onVerifyNow: { appVM.triggerVerify(repoID: repo.id) },
            onEdit: { sheetMode = .edit(repo, focusAuth: false) },
            onReenterCredentials: { appVM.requestReenterCredentials(repoID: repo.id) },
            onOpenLog: { appVM.requestOpenSyncLog(repoID: repo.id) },
            onFreeSpace: {
                Task { await appVM.freeMirrorSpace(for: repo.id) }
            },
            onDelete: {
                pendingDeleteID = repo.id
                showDeleteAlert = true
            }
        )
        .tag(repo.id)
        .listRowBackground(sidebarSelectionBackground(isSelected: isSelected))
    }

    @ViewBuilder
    private func sidebarSelectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.control, style: .continuous)
                .fill(DesignTokens.Surface.selectionTint)
                .padding(.horizontal, DesignTokens.Spacing.xxxs)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }
}
