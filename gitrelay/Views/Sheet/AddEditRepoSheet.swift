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

    var title: String { editingRepo == nil ? "添加仓库" : "编辑仓库" }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("名称").font(.subheadline).fontWeight(.medium)
                        TextField("例如：my-project", text: $vm.name)
                            .textFieldStyle(.roundedBorder)
                        if let err = vm.nameError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }

                    Divider()

                    // Source
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source（源仓库）").font(.subheadline).fontWeight(.medium)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("git@gitlab.com:org/repo.git", text: $vm.srcURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            if let err = vm.srcError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                        AuthFieldView(label: "Source", mode: $vm.srcAuthMode, keyPath: $vm.srcKeyPath, token: $vm.srcToken)
                    }

                    Divider()

                    // Destination
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target（目标仓库）").font(.subheadline).fontWeight(.medium)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("git@github.com:user/repo.git", text: $vm.dstURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            if let err = vm.dstError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                        AuthFieldView(label: "Target", mode: $vm.dstAuthMode, keyPath: $vm.dstKeyPath, token: $vm.dstToken)
                    }

                    Divider()

                    // Frequency
                    FrequencyPickerView(frequency: $vm.frequency)

                    // Mirror warning
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Push mirror 会删除目标仓库中源仓库不存在的分支，目标仓库将成为源仓库的完整镜像。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(editingRepo == nil ? "添加并开始同步" : "保存") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 480)
        .frame(minHeight: 520)
    }

    private func save() {
        guard vm.isValid else { return }
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
