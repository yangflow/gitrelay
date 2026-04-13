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
            LabeledContent("Target") {
                Text(repo.dstURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
    }
}
