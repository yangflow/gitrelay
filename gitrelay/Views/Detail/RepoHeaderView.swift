import SwiftUI

struct RepoHeaderView: View {
    let repo: RepoConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(repo.name)
                .font(.title2)
                .fontWeight(.semibold)

            LabeledContent("Source") {
                Text(repo.srcURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            if repo.targets.count == 1 {
                LabeledContent("Target") {
                    targetLabel(repo.targets[0])
                }
            } else {
                LabeledContent("Targets (\(repo.targets.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(repo.targets.enumerated()), id: \.element.id) { index, target in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                targetLabel(target)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func targetLabel(_ target: MirrorTarget) -> some View {
        HStack(spacing: 6) {
            Text(target.url)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            if !target.enabled {
                Text("已禁用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
