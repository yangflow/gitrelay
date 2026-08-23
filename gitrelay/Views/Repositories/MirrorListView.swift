import SwiftUI

/// Repository health list: name first, mirror route second, status at the edge.
struct MirrorListView: View {
    @Environment(MirrorLibraryModel.self) private var library
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorManagementController.self) private var management
    @Environment(MirrorCacheController.self) private var cache
    @Environment(SecurityController.self) private var security
    @Environment(WorkspaceModel.self) private var workspace
    let onOpen: (UUID) -> Void
    let onAdd: () -> Void
    let onEdit: (MirrorSnapshot) -> Void
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    @State private var tableSelection: UUID?
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteAlert = false
    @State private var isSearchPresented = false

    private var rows: [MirrorListRow] { workspace.displayedMirrorRows }

    var body: some View {
        @Bindable var workspace = workspace
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .searchable(
                text: $workspace.searchText,
                isPresented: $isSearchPresented,
                placement: .toolbar,
                prompt: Text(String.loc("Search Mirrors"))
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    listOptionsMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    addButton
                }
            }
            .onAppear { applyPendingFocusSearch() }
            .onAppear { tableSelection = workspace.selectedMirrorID }
            .onChange(of: workspace.pendingFocusSearch) { _, isPending in
                guard isPending else { return }
                applyPendingFocusSearch()
            }
            .onChange(of: tableSelection) { _, id in
                guard let id else { return }
                onOpen(id)
            }
            .onChange(of: workspace.selectedMirrorID) { _, id in
                guard tableSelection != id else { return }
                tableSelection = id
            }
            .alert(
                String.loc("Delete Mirror"),
                isPresented: $showDeleteAlert,
                presenting: pendingDeleteID
            ) { id in
                Button(String.loc("Delete"), role: .destructive) {
                    Task { await confirmDelete(id: id) }
                }
                Button(String.loc("Cancel"), role: .cancel) { }
            } message: { id in
                let name = library.mirror(id: id)?.name ?? ""
                Text(String(format: String.loc("Delete “%@”? The local mirror cache will also be deleted. This action cannot be undone."), name))
            }
    }

    // MARK: - Toolbar

    private var listOptionsMenu: some View {
        @Bindable var workspace = workspace
        return Menu {
            Section(String.loc("Sort By")) {
                Picker(String.loc("Sort By"), selection: $workspace.sortOrder) {
                    ForEach(MirrorListSortOrder.allCases) { order in
                        Text(sortTitle(order)).tag(order)
                    }
                }
            }

            Section(String.loc("Show")) {
                Picker(String.loc("Show"), selection: $workspace.listFilter) {
                    ForEach(MirrorListFilter.allCases) { filter in
                        Text(filterTitle(filter)).tag(filter)
                    }
                }
            }
        } label: {
            Label(
                String.loc("View Options"),
                systemImage: workspace.listFilter == .all && workspace.sortOrder == .priority
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
        }
        .help(String.loc("View Options"))
        .accessibilityLabel(String.loc("View Options"))
    }

    private func sortTitle(_ order: MirrorListSortOrder) -> String {
        switch order {
        case .priority:
            String.loc("Priority")
        case .name:
            String.loc("Name")
        case .lastSuccess:
            String.loc("Last Success")
        case .nextRun:
            String.loc("Next Run")
        }
    }

    private func filterTitle(_ filter: MirrorListFilter) -> String {
        switch filter {
        case .all:
            String.loc("All")
        case .gitDestinations:
            String.loc("Git Destinations")
        case .archiveDestinations:
            String.loc("Archive Destinations")
        case .multipleDestinations:
            String.loc("Multiple Destinations")
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Label(String.loc("Add Mirror"), systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .help(String.loc("Add Mirror"))
        .accessibilityLabel(String.loc("Add Mirror"))
        .accessibilityIdentifier("mirror-list.add")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if library.mirrors.isEmpty {
            EmptyStateView(
                onAdd: onAdd,
                onExamplePrefill: onExamplePrefill,
                isDropTargeted: isDropTargeted
            )
        } else if rows.isEmpty {
            PaneEmptyStateView(
                systemImage: "magnifyingglass",
                message: String.loc("No Matching Mirrors")
            )
        } else {
            repositoryList
        }
    }

    private var repositoryList: some View {
        List(rows, selection: $tableSelection) { row in
            MirrorListRowView(row: row)
                .tag(row.id)
                .accessibilityIdentifier("mirror-row.\(row.id.uuidString.lowercased())")
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contextMenu {
                    rowContextMenu(id: row.id)
                }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.top, DesignTokens.Spacing.sm)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    @ViewBuilder
    private func rowContextMenu(id: UUID) -> some View {
        if let repo = library.mirror(id: id) {
            let status = operations.statuses[id] ?? .unknown
            let isBusy = status == .syncing || status == .queued

            if isBusy {
                Button(String.loc("Cancel")) {
                    operations.cancelSync(mirrorID: id)
                }
            } else {
                Button(String.loc("Sync Now")) {
                    operations.triggerSync(mirrorID: id)
                }
            }

            Button(String.loc("Verify Now")) {
                operations.triggerVerify(mirrorID: id)
            }
            .disabled(isBusy)

            Button(String.loc("Free Space")) {
                Task { await cache.clean(mirrorID: id) }
            }
            .disabled(isBusy)

            Button(String.loc("Open Log")) {
                workspace.requestOpenSyncLog(mirrorID: id)
            }

            Divider()

            Button(String.loc("Edit")) {
                onEdit(repo)
            }
            Button(String.loc("Delete"), role: .destructive) {
                pendingDeleteID = id
                showDeleteAlert = true
            }
        }
    }

    // MARK: - Actions

    private func applyPendingFocusSearch() {
        guard workspace.consumePendingFocusSearch() else { return }
        isSearchPresented = true
    }

    private func confirmDelete(id: UUID) async {
        guard await security.authorize(.deleteRepository) else { return }
        management.delete(mirrorID: id)
    }
}

private struct MirrorListRowView: View {
    let row: MirrorListRow

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            repositoryMark

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(row.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: DesignTokens.Spacing.xs)

                    healthLabel
                }

                HStack(spacing: DesignTokens.Spacing.xs) {
                    routeEndpoint(label: row.sourceLabel, provider: row.sourceProvider)
                        .help(row.sourceURL)

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    routeEndpoint(label: row.destinationLabel, provider: row.destinationProvider)
                        .help(row.destinationURL)

                    if row.destinationCount > 1 {
                        Text(verbatim: "+\(row.destinationCount - 1)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .help(
                                String(
                                    format: String.loc("%lld more targets"),
                                    row.destinationCount - 1
                                )
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Spacer(minLength: 0)
                    activityLabel
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .contentShape(Rectangle())
        .help(row.healthDetail ?? healthTitle)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var repositoryMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.control, style: .continuous)
                .fill(providerTint(row.sourceProvider).opacity(0.12))

            ProviderIdentityIcon(provider: row.sourceProvider, size: 16)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var healthLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(healthTint)
                .frame(width: 6, height: 6)
            Text(healthTitle)
                .lineLimit(1)
        }
        .font(.caption.weight(healthIsActionable ? .semibold : .medium))
        .foregroundStyle(healthIsActionable ? healthTint : Color.secondary)
    }

    @ViewBuilder
    private var activityLabel: some View {
        switch row.activity {
        case .queued(let position):
            Label(
                String(format: String.loc("Queue Position %lld"), position),
                systemImage: "clock"
            )
            .lineLimit(1)
        case .synchronizing(let phase):
            HStack(spacing: DesignTokens.Spacing.xs) {
                ProgressView()
                    .controlSize(.mini)
                Text(phase.displayCaption)
                    .lineLimit(1)
            }
        case .verifying:
            Label(String.loc("Verifying..."), systemImage: "checkmark.shield")
                .lineLimit(1)
        case .paused:
            Label(String.loc("Paused"), systemImage: "pause.circle")
                .lineLimit(1)
        case .lastSuccess(let date):
            Text(String(format: String.loc("Last success: %@"), relative(date)))
                .lineLimit(1)
        case .nextRun(let date):
            Text(String(format: String.loc("Next run: %@"), relative(date)))
                .lineLimit(1)
        case .manual:
            Text(String.loc("Manual schedule"))
                .lineLimit(1)
        }
    }

    private func routeEndpoint(label: String, provider: GitProvider?) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ProviderIdentityIcon(provider: provider, size: 12)
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var healthTitle: String {
        switch row.health {
        case .needsCredentials:
            String.loc("Needs credentials")
        case .needsSetup:
            String.loc("Needs Setup")
        case .failed:
            String.loc("Failed")
        case .diverged:
            String.loc("Diverged")
        case .stale:
            String.loc("Stale")
        case .neverRun:
            String.loc("Never Run")
        case .healthy:
            String.loc("Healthy")
        }
    }

    private var healthTint: Color {
        switch row.health {
        case .healthy:
            DesignTokens.StatusColor.success
        case .needsCredentials, .needsSetup, .failed:
            DesignTokens.StatusColor.escalatedFailure
        case .diverged, .stale:
            DesignTokens.StatusColor.warning
        case .neverRun:
            DesignTokens.StatusColor.unknown
        }
    }

    private var healthIsActionable: Bool { row.health != .healthy }

    private func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    private func providerTint(_ provider: GitProvider?) -> Color {
        switch provider {
        case .github:
            Color.primary
        case .gitlab:
            Color(red: 0.94, green: 0.32, blue: 0.24)
        case .gitea:
            DesignTokens.StatusColor.success
        case nil:
            Color.secondary
        }
    }
}
