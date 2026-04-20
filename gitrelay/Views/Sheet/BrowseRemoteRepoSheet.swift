import SwiftUI

struct BrowseRemoteRepoSheet: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(\.dismiss) private var dismiss
    @State private var vm = BrowseRemoteRepoViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640)
        .frame(minHeight: 560)
        .onAppear {
            vm.restorePersistedToken()
            vm.restorePersistedTargetCreateToken()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(headerTitle).font(.headline)
            Spacer()
            Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 12)
    }

    private var headerTitle: String {
        switch vm.phase {
        case .connect:          "浏览并选择远端仓库"
        case .selecting:        "选择要镜像的仓库"
        case .configureTarget:  "配置目标仓库"
        case .submitting:       "正在创建目标仓库"
        case .result:           "执行结果"
        }
    }

    private var phaseLabel: String {
        switch vm.phase {
        case .connect:          "1 / 3"
        case .selecting:        "2 / 3"
        case .configureTarget:  "3 / 3"
        case .submitting:       "处理中…"
        case .result:           "完成"
        }
    }

    // MARK: - Content dispatch

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .connect:         connectView
        case .selecting:       selectView
        case .configureTarget: targetView
        case .submitting:      submittingView
        case .result:          resultView
        }
    }

    // MARK: - Phase 1

    private var connectView: some View {
        Form {
            Section("Provider") {
                Picker("类型", selection: $vm.provider) {
                    ForEach(GitProvider.listingCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.provider) { _, _ in vm.restorePersistedToken() }

                Text(vm.provider.tokenHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if vm.provider == .gitlab {
                Section("GitLab Host(自建实例可选)") {
                    TextField("https://gitlab.company.com", text: $vm.gitlabHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Text("留空则使用 gitlab.com。会自动追加 /api/v4 路径。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Personal Access Token") {
                SecureField("仅用于拉取仓库列表,不用于 git 同步", text: $vm.token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Toggle("保存到 Keychain(下次自动填充)", isOn: $vm.rememberToken)
            }

            Section("范围") {
                Picker("选择范围", selection: $vm.scopeKind) {
                    ForEach(BrowseRemoteRepoViewModel.ScopeKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                if vm.scopeKind == .organization {
                    TextField(vm.provider == .github ? "组织名称 (如 anthropic)" : "群组路径 (如 gitlab-org/charts)",
                              text: $vm.organizationName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let err = vm.connectError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Phase 2

    private var selectView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索名称或描述", text: $vm.searchText)
                    .textFieldStyle(.plain)
                Spacer()
                Button("全选当前") { vm.selectAllVisible() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Button("清空") { vm.clearSelection() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(vm.filteredRepos) { repo in
                    RepoPickerRow(
                        repo: repo,
                        isSelected: vm.selectedIDs.contains(repo.id),
                        onToggle: { vm.toggleSelection(repo) }
                    )
                }
                if vm.hasMore {
                    HStack {
                        Spacer()
                        Button(vm.isLoading ? "加载中..." : "加载更多") {
                            Task { await vm.loadMore() }
                        }
                        .disabled(vm.isLoading)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Phase 3

    private var targetView: some View {
        Form {
            Section("已选择 \(vm.selectedIDs.count) 个仓库") {
                Text("源 URL 由所选仓库自动生成(按下方的源认证方式选择 SSH 或 HTTPS)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("源仓库认证(用于 git clone/fetch)") {
                AuthFieldView(
                    label: "Source",
                    mode: $vm.sourceAuthMode,
                    keyPath: $vm.sourceKeyPath,
                    token: $vm.sourceToken
                )
            }

            Section("目标仓库") {
                Toggle("在目标端自动创建仓库 (Gitea)", isOn: $vm.targetAutoCreate)
                Text(vm.targetAutoCreate
                     ? "使用 Gitea API 按所选仓库批量创建; 名称冲突时复用已存在仓库。"
                     : "目标仓库需要预先存在; 使用 {name} 模板生成 URL。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if vm.targetAutoCreate {
                autoCreateFields
            } else {
                Section("目标 URL 模板") {
                    TextField("git@github.com:myuser/{name}.git", text: $vm.targetURLTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Text("使用 {name} 作为仓库名占位符。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("目标仓库认证(用于 git push)") {
                AuthFieldView(
                    label: "Target",
                    mode: $vm.targetAuthMode,
                    keyPath: $vm.targetKeyPath,
                    token: $vm.targetToken
                )
            }

            Section("命名 & 频率") {
                TextField("名称前缀(可选)", text: $vm.namePrefix)
                    .textFieldStyle(.roundedBorder)
                FrequencyPickerView(frequency: $vm.frequency)
            }

            if !vm.selectedRepos.isEmpty {
                Section("预览(前 3 条)") {
                    ForEach(vm.selectedRepos.prefix(3), id: \.id) { repo in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.previewName(for: repo)).font(.caption).bold()
                            Text("src: \(vm.sourceURL(for: repo))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("dst: \(vm.previewURL(for: repo))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let err = vm.submitError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var autoCreateFields: some View {
        Section("Gitea Host") {
            TextField("https://gitea.company.com", text: $vm.targetCreateHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            Text("自动追加 /api/v1 路径。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Gitea API Token") {
            SecureField("需要 write:repository 权限", text: $vm.targetCreateToken)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            Toggle("保存到 Keychain(下次自动填充)", isOn: $vm.rememberTargetCreateToken)
        }

        Section("命名空间") {
            Picker("位置", selection: $vm.targetNamespaceKind) {
                ForEach(BrowseRemoteRepoViewModel.NamespaceKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)

            switch vm.targetNamespaceKind {
            case .currentUser:
                Text("将创建在当前 Token 所属用户名下。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .organization:
                TextField("组织名称", text: $vm.targetNamespaceOwner)
                    .textFieldStyle(.roundedBorder)
            case .adminForUser:
                TextField("目标用户名(Token 需为管理员)", text: $vm.targetNamespaceOwner)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("创建为 Private 仓库", isOn: $vm.targetVisibilityPrivate)
        }
    }

    // MARK: - Phase 4 — submitting

    private var submittingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("正在处理 \(vm.submitProgress) / \(vm.submitTotal)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase 5 — result

    private var resultView: some View {
        let succeeded = vm.batchResults.reduce(into: 0) { acc, o in
            if case .success = o { acc += 1 }
        }
        let existed = vm.batchResults.reduce(into: 0) { acc, o in
            if case .success(_, _, let ex) = o, ex { acc += 1 }
        }
        let failed = vm.batchResults.reduce(into: 0) { acc, o in
            if case .failed = o { acc += 1 }
        }

        return Form {
            Section {
                HStack(spacing: 14) {
                    Label("成功 \(succeeded)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if existed > 0 {
                        Label("复用 \(existed)", systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    if failed > 0 {
                        Label("失败 \(failed)", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            Section("详情") {
                ForEach(vm.batchResults) { outcome in
                    BatchOutcomeRow(outcome: outcome)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if vm.phase != .connect, vm.phase != .submitting, vm.phase != .result {
                Button("上一步") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if vm.phase != .submitting {
                Button(vm.phase == .result ? "关闭" : "取消") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            primaryButton
        }
        .padding(16)
    }

    @ViewBuilder private var primaryButton: some View {
        switch vm.phase {
        case .connect:
            Button(vm.isLoading ? "加载中..." : "加载仓库") {
                Task { await vm.loadFirstPage() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canAdvanceToSelect || vm.isLoading)
            .keyboardShortcut(.return)
        case .selecting:
            Button("下一步 (\(vm.selectedIDs.count))") {
                vm.phase = .configureTarget
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedIDs.isEmpty)
            .keyboardShortcut(.return)
        case .configureTarget:
            Button(vm.targetAutoCreate
                   ? "创建并添加 \(vm.selectedIDs.count) 个"
                   : "添加 \(vm.selectedIDs.count) 个仓库") {
                Task { await vm.runBatch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canSubmit)
            .keyboardShortcut(.return)
        case .submitting:
            EmptyView()
        case .result:
            let count = vm.successfulConfigs.count
            Button("添加 \(count) 个到同步列表") {
                let configs = vm.successfulConfigs
                vm.persistTokensForSuccessfulConfigs()
                appVM.addRepos(configs, triggerSync: true)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
            .keyboardShortcut(.return)
        }
    }

    private func goBack() {
        switch vm.phase {
        case .connect:          break
        case .selecting:        vm.phase = .connect
        case .configureTarget:  vm.phase = .selecting
        case .submitting:       break
        case .result:           break
        }
    }
}

private struct RepoPickerRow: View {
    let repo: RemoteRepo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(repo.fullName).font(.caption).bold()
                        if repo.isPrivate {
                            Text("private")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    if let d = repo.description, !d.isEmpty {
                        Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BatchOutcomeRow: View {
    let outcome: BrowseRemoteRepoViewModel.BatchOutcome

    var body: some View {
        switch outcome {
        case .success(let repo, _, let existed):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: existed
                      ? "arrow.counterclockwise.circle.fill"
                      : "checkmark.circle.fill")
                    .foregroundStyle(existed ? Color.blue : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.fullName).font(.caption).bold()
                    Text(existed ? "远端已存在,将复用" : "创建成功")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .failed(let repo, let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.fullName).font(.caption).bold()
                    Text(message).font(.caption2).foregroundStyle(.red)
                }
                Spacer()
            }
        }
    }
}
