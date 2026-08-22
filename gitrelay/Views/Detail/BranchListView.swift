import SwiftUI

struct BranchListView: View {
    let branches: [BranchInfo]
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if branches.isEmpty {
                Text(String.loc("No Branches Detected (Visible After Sync)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(branches) { branch in
                        HStack {
                            Image(systemName: branch.isDefault ? "arrow.branch" : "line.diagonal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(branch.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Text(branch.tipSHA.truncatingSHA)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxxs)
                        if branch.id != branches.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
