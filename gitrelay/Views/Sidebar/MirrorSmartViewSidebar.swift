import SwiftUI

/// The continuity workspace navigator. It scopes the mirror list without
/// becoming a second set of feature destinations.
struct MirrorSmartViewSidebar: View {
    @Environment(MirrorLibraryModel.self) private var library
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorSchedulingController.self) private var scheduling
    @Environment(AppPreferencesModel.self) private var preferences
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                Section {
                    ForEach(MirrorSmartViewQuery.primaryViews) { smartView in
                        row(smartView)
                            .tag(smartView)
                    }
                }

                if !workspace.labelSmartViews.isEmpty {
                    Section(String.loc("Labels")) {
                        ForEach(workspace.labelSmartViews) { smartView in
                            row(smartView)
                                .tag(smartView)
                        }
                    }
                }
            }
            .gitRelaySidebarListStyle()

            SidebarFooterView(
                summary: SidebarFooterSummary.make(
                    repos: library.mirrors,
                    statuses: operations.statuses,
                    pauseReason: scheduling.pauseReason
                ),
                onTogglePause: toggleScheduledSyncPause
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selection: Binding<MirrorSmartView?> {
        Binding(
            get: { workspace.selectedSmartView },
            set: { newValue in
                guard let newValue else { return }
                workspace.selectSmartView(newValue)
            }
        )
    }

    private func row(_ smartView: MirrorSmartView) -> some View {
        SidebarNavigationRow(
            title: smartView.title,
            systemImage: smartView.systemImage,
            tint: smartView.tint,
            count: workspace.count(for: smartView)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("smart-view.\(smartView.id)")
    }

    private func toggleScheduledSyncPause() {
        var value = preferences.notificationStore.preferences
        value.scheduledSyncManuallyPaused.toggle()
        preferences.notificationStore.preferences = value
    }
}

private extension MirrorSmartView {
    var title: String {
        switch self {
        case .needsAttention:
            String.loc("Needs Attention")
        case .allMirrors:
            String.loc("All Mirrors")
        case .running:
            String.loc("Running")
        case .paused:
            String.loc("Paused")
        case .label(let label):
            label
        }
    }

    var systemImage: String {
        switch self {
        case .needsAttention:
            "exclamationmark.triangle"
        case .allMirrors:
            "square.stack.3d.up"
        case .running:
            "arrow.triangle.2.circlepath"
        case .paused:
            "pause.circle"
        case .label:
            "tag"
        }
    }

    var tint: Color {
        switch self {
        case .needsAttention:
            .orange
        case .allMirrors:
            .blue
        case .running:
            .purple
        case .paused:
            .secondary
        case .label:
            .teal
        }
    }
}
