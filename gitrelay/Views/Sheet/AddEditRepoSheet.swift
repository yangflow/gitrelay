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

                Section("校验分支") {
                    TextField("main", text: $vm.defaultBranch)
                        .font(.system(.body, design: .monospaced))
                    Text("完整性校验比对 src/dst 上该分支的 tip 与 tree hash。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("破坏性推送保护") {
                    Picker("策略", selection: $vm.destructivePushPolicy) {
                        ForEach(DestructivePushPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(vm.destructivePushPolicy.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label {
                        Text("GitRelay 会先执行 dry-run。严格保护会在删除或强制更新前弹出确认弹窗;取消则阻断并记失败。自动执行保留传统 mirror 行为。")
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
        .frame(minHeight: 620)
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
