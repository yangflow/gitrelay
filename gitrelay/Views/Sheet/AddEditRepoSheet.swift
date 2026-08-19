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
                        remoteURL: vm.srcURL,
                        mode: $vm.srcAuthMode,
                        keyPath: $vm.srcKeyPath,
                        token: $vm.srcToken
                    )
                }

                Section {
                    ForEach(Array(vm.targets.enumerated()), id: \.element.id) { index, _ in
                        MirrorTargetCardView(
                            index: index,
                            target: binding(for: vm.targets[index].id),
                            error: vm.targetErrors[vm.targets[index].id],
                            canRemove: vm.targets.count > 1,
                            onRemove: { vm.removeTarget(id: vm.targets[index].id) }
                        )
                    }

                    Button {
                        vm.addTarget()
                    } label: {
                        Label("添加目标", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Targets(目标仓库)")
                } footer: {
                    Text("同一源仓库可镜像到多个目标；禁用的目标在同步时跳过。")
                        .font(.caption)
                }

                Section("同步频率") {
                    FrequencyPickerView(frequency: $vm.frequency)
                }

                Section("标签") {
                    TagTokenInputView(
                        tags: $vm.tags,
                        suggestions: appVM.allKnownTags
                    )
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
        .frame(minHeight: 680)
    }

    private func binding(for id: UUID) -> Binding<MirrorTargetDraft> {
        Binding(
            get: { vm.targets.first(where: { $0.id == id }) ?? MirrorTargetDraft() },
            set: { newValue in
                guard let index = vm.targets.firstIndex(where: { $0.id == id }) else { return }
                vm.targets[index] = newValue
            }
        )
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
