import SwiftUI

struct DestructivePushConfirmationSheet: View {
    let repoName: String
    let targetURL: String?
    let plan: DestructivePushPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text("破坏性镜像推送确认")
                        .font(.headline)
                    Text("「\(repoName)」")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let targetURL {
                        Text(targetURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(plan.confirmationPrompt)
                        .font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !plan.deletedRefs.isEmpty {
                        refSection(
                            title: "将删除 \(plan.deletedRefs.count) 个 ref",
                            refs: plan.deletedRefs,
                            symbol: "trash",
                            tint: .red
                        )
                    }
                    if !plan.forcedUpdateRefs.isEmpty {
                        refSection(
                            title: "将强制更新 \(plan.forcedUpdateRefs.count) 个 ref",
                            refs: plan.forcedUpdateRefs,
                            symbol: "arrow.triangle.2.circlepath",
                            tint: .orange
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxHeight: 320)

            Divider()

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.escape)
                Button("继续", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 480)
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func refSection(
        title: String,
        refs: [String],
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(refs, id: \.self) { ref in
                    Text(ref)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
