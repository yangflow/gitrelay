import SwiftUI

/// 仓库 home: the source → target pair table with search and add.
struct RepoPairTableView: View {
    @Environment(AppViewModel.self) private var appVM
    let onOpen: (UUID) -> Void
    let onAdd: () -> Void
    let onEdit: (RepoConfig) -> Void
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    @State private var tableSelection: UUID?
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteAlert = false
    @FocusState private var isSearchFieldFocused: Bool

    private var rows: [RepoPairRow] {
        RepoPairTable.rows(repos: appVM.displayedSidebarRepos, statuses: appVM.statuses)
    }

    var body: some View {
        @Bindable var appVM = appVM
        VStack(spacing: 0) {
            PaneHeaderView(
                title: MainSidebarItem.repositories.title,
                subtitle: String(localized: "\(appVM.repos.count) repos")
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    searchField(text: $appVM.sidebarSearchText)
                    addButton
                }
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { applyPendingFocusSearch() }
        .onChange(of: appVM.pendingFocusSidebarSearch) { _, isPending in
            guard isPending else { return }
            applyPendingFocusSearch()
        }
        .onChange(of: tableSelection) { _, id in
            guard let id else { return }
            tableSelection = nil
            onOpen(id)
        }
        .alert(
            String(localized: "Delete Repository"),
            isPresented: $showDeleteAlert,
            presenting: pendingDeleteID
        ) { id in
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await confirmDelete(id: id) }
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: { id in
            let name = appVM.repos.first(where: { $0.id == id })?.name ?? ""
            Text(String(localized: "Delete “\(name)”? The local mirror cache will also be deleted. This action cannot be undone."))
        }
    }

    // MARK: - Header

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(String(localized: "Search Repositories"), text: text)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear Search"))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(width: 260, height: DesignTokens.Size.searchFieldMinHeight)
        .background(DesignTokens.Surface.searchFieldFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.control,
                style: .continuous
            )
        )
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .frame(
                    width: DesignTokens.Size.searchFieldMinHeight,
                    height: DesignTokens.Size.searchFieldMinHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .help(String(localized: "Add a Repository Manually"))
        .accessibilityLabel(String(localized: "Add Repository"))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appVM.repos.isEmpty {
            EmptyStateView(
                onExamplePrefill: onExamplePrefill,
                isDropTargeted: isDropTargeted
            )
        } else if rows.isEmpty {
            PaneEmptyStateView(
                systemImage: "magnifyingglass",
                message: String(localized: "No Matching Repositories")
            )
        } else {
            table
        }
    }

    private var table: some View {
        Table(rows, selection: $tableSelection) {
            TableColumn(String(localized: "Source")) { row in
                RepoPairPathCell(
                    label: row.sourceLabel,
                    provider: row.sourceProvider,
                    fullURL: row.sourceURL
                )
            }
            .width(
                min: DesignTokens.Layout.pairTablePathColumnMin,
                ideal: DesignTokens.Layout.pairTablePathColumnIdeal
            )

            TableColumn(String(localized: "Target")) { row in
                RepoPairPathCell(
                    label: row.targetLabel,
                    provider: row.targetProvider,
                    fullURL: row.targetURL,
                    additionalCount: row.additionalTargetCount
                )
            }
            .width(
                min: DesignTokens.Layout.pairTablePathColumnMin,
                ideal: DesignTokens.Layout.pairTablePathColumnIdeal
            )

            TableColumn(String(localized: "Status")) { row in
                RepoPairStatusCell(status: row.status, detail: row.statusDetail)
            }
            .width(
                min: DesignTokens.Layout.pairTableStatusColumnMin,
                ideal: DesignTokens.Layout.pairTableStatusColumnIdeal
            )

            TableColumn(String(localized: "Last")) { row in
                Text(row.lastSyncedText ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(
                min: DesignTokens.Layout.pairTableLastColumnMin,
                ideal: DesignTokens.Layout.pairTableLastColumnIdeal
            )
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            rowContextMenu(ids: ids)
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            onOpen(id)
        }
        .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
        .padding(.bottom, DesignTokens.Spacing.paneHeaderHorizontal)
    }

    @ViewBuilder
    private func rowContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first, let repo = appVM.repos.first(where: { $0.id == id }) {
            let status = appVM.statuses[id] ?? .unknown
            let isBusy = status == .syncing || status == .queued

            if isBusy {
                Button(String(localized: "Cancel")) {
                    appVM.cancelSync(repoID: id)
                }
            } else {
                Button(String(localized: "Sync Now")) {
                    appVM.triggerSync(repoID: id)
                }
            }

            Button(String(localized: "Verify Now")) {
                appVM.triggerVerify(repoID: id)
            }
            .disabled(isBusy)

            Button(String(localized: "Free Space")) {
                Task { await appVM.freeMirrorSpace(for: id) }
            }
            .disabled(isBusy)

            Button(String(localized: "Open Log")) {
                appVM.requestOpenSyncLog(repoID: id)
            }

            Divider()

            Button(String(localized: "Edit")) {
                onEdit(repo)
            }
            Button(String(localized: "Delete"), role: .destructive) {
                pendingDeleteID = id
                showDeleteAlert = true
            }
        }
    }

    // MARK: - Actions

    private func applyPendingFocusSearch() {
        guard appVM.consumePendingFocusSidebarSearch() else { return }
        isSearchFieldFocused = true
    }

    private func confirmDelete(id: UUID) async {
        guard await appVM.authorizeSensitiveAction(.deleteRepository) else { return }
        appVM.deleteRepo(id: id)
    }
}

/// One 源 / 目标 cell: provider glyph plus the shortest unambiguous path.
private struct RepoPairPathCell: View {
    let label: String
    let provider: GitProvider?
    let fullURL: String
    var additionalCount: Int = 0

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: provider?.symbolName ?? "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)

            if additionalCount > 0 {
                Text(verbatim: "+\(additionalCount)")
                    .font(.caption2)
                    .monospacedDigit()
                    .padding(.horizontal, DesignTokens.Spacing.chipHorizontal)
                    .padding(.vertical, 1)
                    .background(DesignTokens.Surface.chipFill)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.CornerRadius.chip,
                            style: .continuous
                        )
                    )
                    .help(String(localized: "\(additionalCount) more targets"))
            }
        }
        .help(fullURL)
    }
}

/// Green check + 成功, or red dot + 失败. In-flight states stay neutral.
private struct RepoPairStatusCell: View {
    let status: RepoPairStatusKind
    let detail: String?

    var body: some View {
        Label {
            Text(status.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: status.systemImage)
                .font(status == .failed ? .caption2 : .caption)
                .foregroundStyle(tint)
        }
        .help(detail ?? status.title)
        .accessibilityLabel(detail.map { "\(status.title). \($0)" } ?? status.title)
    }

    private var tint: Color {
        switch status {
        case .succeeded:
            DesignTokens.StatusColor.success
        case .failed:
            DesignTokens.StatusColor.escalatedFailure
        case .syncing, .queued, .notSynced:
            Color.secondary
        }
    }
}
