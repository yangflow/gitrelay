import SwiftUI

struct BranchListView: View {
    let branches: [BranchInfo]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Branches")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if branches.isEmpty {
                Text("No Branches Detected (Visible After Sync)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        if branch.id != branches.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
        }
    }
}
