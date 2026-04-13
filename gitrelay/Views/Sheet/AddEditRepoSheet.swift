import SwiftUI

struct AddEditRepoSheet: View {
    let editingRepo: RepoConfig?
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss

    @State private var vm: AddEditRepoViewModel

    init(repo: RepoConfig?) {
        editingRepo = repo
        _vm = State(initialValue: AddEditRepoViewModel(editing: repo))
    }

    private var title: String { editingRepo == nil ? "添加仓库" : "编辑仓库" }
    private var primaryActionTitle: String { editingRepo == nil ? "添加并开始同步" : "保存" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section("名称") {
                    TextField("例如:my-project", text: $vm.name)
                    if let err = vm.nameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Source(源仓库)") {
                    TextField("git@gitlab.com:org/repo.git", text: $vm.srcURL)
                        .font(.system(.caption, design: .monospaced))
                    if let err = vm.srcError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    AuthFieldView(
                        label: "Source",
                        mode: $vm.srcAuthMode,
                        keyPath: $vm.srcKeyPath,
                        token: $vm.srcToken
                    )
                }

                Section("Target(目标仓库)") {
                    TextField("git@github.com:user/repo.git", text: $vm.dstURL)
                        .font(.system(.caption, design: .monospaced))
                    if let err = vm.dstError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    AuthFieldView(
                        label: "Target",
                        mode: $vm.dstAuthMode,
                        keyPath: $vm.dstKeyPath,
                        token: $vm.dstToken
                    )
                }

                Section("同步频率") {
                    FrequencyPickerView(frequency: $vm.frequency)
                }

                Section {
                    Label {
                        Text("Push mirror 会删除目标仓库中源仓库不存在的分支,目标仓库将成为源仓库的完整镜像。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(primaryActionTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(minHeight: 560)
    }

    private func save() {
        guard vm.validate() else { return }
        let config = vm.buildRepoConfig()
        vm.saveTokensToKeychain(repoID: config.id)
        if editingRepo != nil {
            appVM.updateRepo(config)
        } else {
            appVM.addRepo(config)
            appVM.triggerSync(repoID: config.id)
        }
        dismiss()
    }
}
