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
                    Text("同一源仓库可镜像到多个目标；可选择 Git 远程或文件系统归档 (tar.gz / zip / git bundle)。禁用的目标在同步时跳过。")
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

                Section("Release 镜像") {
                    Toggle("镜像 Releases 及二进制 assets", isOn: $vm.mirrorReleases)
                    Text("同步 git 仓库后，将源仓库 Release 的 tag/title/body 与 .dmg、.tar.gz 等附件增量复制到每个已启用目标。需要 GitHub/GitLab API Token。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("允许 Webhook 即时同步", isOn: $vm.webhookEnabled)
                    if vm.webhookEnabled {
                        if let editing = editingRepo {
                            Text("路径：/hook/\(editing.webhookPathID)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)

                            let url = appVM.webhookURL(for: editing)
                            HStack {
                                Text(url)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                Spacer()
                                Button("复制 URL") { ClipboardService.copy(url) }
                                    .font(.caption)
                            }

                            if let secret = WebhookSecretStore.loadSecret(repoID: editing.id) {
                                HStack {
                                    Text("HMAC 密钥已存入 Keychain")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("复制密钥") { ClipboardService.copy(secret) }
                                        .font(.caption)
                                }
                            }
                        } else {
                            Text("保存后生成路径 /hook/<repo-id> 与 HMAC 密钥（写入 Keychain）。请同时在设置中启用本机监听。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("保存时尝试通过 GitHub API 注册 webhook", isOn: $vm.registerWebhookOnSave)
                        if vm.registerWebhookOnSave {
                            if let disclosure = ProviderTokenUsage.webhookRegistration(provider: .github).disclosureText {
                                Text(disclosure)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            SecureField("GitHub Token（需 admin:repo_hook）", text: $vm.webhookRegistrationToken)
                            TokenScopeBannerView(validation: vm.webhookScopeValidation)
                            if let message = vm.webhookRegistrationMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Webhook")
                } footer: {
                    Text("收到校验通过的 push 事件后立即同步，不受频率调度限制。需在「设置 → Webhook」启用本机监听；外网暴露使用 Cloudflare Tunnel / Tailscale Funnel（可选）。")
                }

                Section {
                    DisclosureGroup("高级选项") {
                        TextField("克隆深度（留空 = 全量历史）", text: $vm.depthText)
                            .font(.system(.body, design: .monospaced))
                        if let err = vm.depthError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fetch refspecs（每行一条）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $vm.refSpecsText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 72)
                        }

                        Text("默认同步所有分支与 tag。可改为仅 main + v* tag，例如：\n+refs/heads/main:refs/heads/main\n+refs/tags/v*:refs/tags/v*")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let warning = vm.partialSyncWarning {
                            Label {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
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
        .frame(minHeight: 760)
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

        if vm.webhookEnabled, vm.registerWebhookOnSave {
            let hookURL = appVM.webhookURL(for: config)
            let token = vm.webhookRegistrationToken
            Task {
                let message = await Self.registerGitHubWebhook(
                    repo: config,
                    hookURL: hookURL,
                    token: token
                )
                await MainActor.run {
                    if let message {
                        appVM.errorMessage = message
                    }
                }
            }
        }
        dismiss()
    }

    private static func registerGitHubWebhook(
        repo: RepoConfig,
        hookURL: String,
        token: String
    ) async -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Webhook 自动注册已跳过：未提供 GitHub Token。"
        }
        guard let path = GitRemoteRepoPath.parse(from: repo.srcURL), !path.namespace.isEmpty else {
            return "Webhook 自动注册已跳过：无法从源 URL 解析 owner/repo。"
        }
        let client = GitHubWebhookAPIClient(token: trimmed)
        do {
            let scopes = try await client.fetchTokenScopes()
            let validation = ProviderTokenScope.validate(
                grantedScopes: scopes,
                usage: .webhookRegistration(provider: .github)
            )
            guard validation.isFullyAuthorized else {
                return "Webhook 自动注册已跳过：Token 缺少 admin:repo_hook。"
            }
            let secret = try WebhookSecretStore.ensureSecret(repoID: repo.id)
            let registration = try await client.createPushHook(
                owner: path.namespace,
                repo: path.name,
                hookURL: hookURL,
                secret: secret
            )
            return "已在 GitHub 注册 webhook #\(registration.id)。"
        } catch {
            return "Webhook 自动注册失败：\(error.localizedDescription)"
        }
    }
}
