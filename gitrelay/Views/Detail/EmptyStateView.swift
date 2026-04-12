import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("GitRelay")
                .font(.title2)
                .fontWeight(.semibold)

            Text("把任意 Git 仓库镜像同步到另一个仓库\nGitLab → GitHub · Gitea · Gitee")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("添加第一个仓库") { onAdd() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
