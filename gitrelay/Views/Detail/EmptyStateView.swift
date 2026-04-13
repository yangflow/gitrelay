import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("GitRelay", systemImage: "arrow.left.arrow.right.circle")
        } description: {
            Text("把任意 Git 仓库镜像同步到另一个仓库\nGitLab → GitHub · Gitea · Gitee")
        } actions: {
            Button("添加第一个仓库", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
