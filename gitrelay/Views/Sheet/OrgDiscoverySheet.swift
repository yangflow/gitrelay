import SwiftUI

/// Quiet sheet for a newly discovered org repo when auto-add is off (#108).
struct OrgDiscoverySheet: View {
  let item: OrgPendingDiscoveryItem
  let canJoinAndSync: Bool
  let onDecision: (OrgDiscoveryDecision) -> Void

  private var sourcePath: String {
    OrgDiscoverySheetCopy.sourceHostPath(
      provider: item.provider,
      fullName: item.repo.fullName,
      customHost: item.gitlabHost
    )
  }

  private var targetPath: String {
    OrgDiscoverySheetCopy.targetPreview(for: item.repo, template: item.template)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
        Text(OrgDiscoverySheetCopy.title)
          .font(.headline)
        Text(
          OrgDiscoverySheetCopy.discoverySentence(
            organizationName: item.organizationName,
            repoName: item.repo.name
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        mappingRow
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .gitRelaySheetHeaderPadding()

      Divider()

      HStack {
        Button(OrgDiscoverySheetCopy.ignoreTitle) {
          onDecision(.ignore)
        }
        Spacer()
        Button(OrgDiscoverySheetCopy.laterTitle) {
          onDecision(.later)
        }
        Button(OrgDiscoverySheetCopy.joinAndSyncTitle) {
          onDecision(.joinAndSync)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return)
        .disabled(!canJoinAndSync)
      }
      .gitRelaySheetFooterPadding()
    }
    .frame(width: 480)
    .frame(minHeight: 200)
    .gitRelayChrome(.sheet)
  }

  private var mappingRow: some View {
    HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
      mappingColumn(
        title: OrgDiscoverySheetCopy.sourceLabel,
        value: sourcePath
      )
      Image(systemName: "arrow.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, DesignTokens.Spacing.sm)
      mappingColumn(
        title: OrgDiscoverySheetCopy.targetLabel,
        value: targetPath,
        secondary: targetPath == OrgDiscoverySheetCopy.targetFromTemplatePlaceholder
      )
    }
    .padding(DesignTokens.Spacing.popoverChromeVertical)
    .gitRelayPanelSurface(
      fill: DesignTokens.Surface.panelFill,
      cornerRadius: DesignTokens.CornerRadius.banner
    )
  }

  private func mappingColumn(
    title: String,
    value: String,
    secondary: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(secondary ? .secondary : .primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
