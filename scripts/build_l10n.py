#!/usr/bin/env python3
"""Replace Chinese Swift literals with English and build string catalogs."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT_ROOTS = (ROOT / "gitrelay", ROOT / "GitRelayCore")
SPECIAL_FREQUENCY_FILES = {"SyncFrequency.swift", "VerificationFrequency.swift"}
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
STRING_LITERAL_RE = re.compile(r'"((?:\\.|[^"\\])*)"')
PERSISTED_CASE_RE = re.compile(
    r'^\s*case\s+\w+\s*=\s*"[^"]*[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff][^"]*"\s*(?://.*)?$'
)
INTERPOLATION_START = r"\("


# Keys are the exact contents of Chinese-containing Swift string literals.
# Backslashes are doubled here because this is Python source; at runtime they
# match Swift interpolation and escape sequences verbatim.
TRANSLATIONS: dict[str, str] = {
    # GitRelayCore
    "未找到 ssh-keygen，请确认 macOS 命令行工具已安装。": "ssh-keygen was not found. Make sure the macOS Command Line Tools are installed.",
    "请指定私钥保存路径。": "Specify a path for the private key.",
    "密钥文件已存在：\\(path)": "A key file already exists at: \\(path)",
    "ssh-keygen 执行失败。": "ssh-keygen failed.",
    "未找到公钥文件：\\(path)": "Public key file not found: \\(path)",
    "已阻断破坏性镜像推送: \\(plan.summary)。可再次同步并在确认弹窗中选择继续,或将策略改为自动执行。": "Destructive mirror push blocked: \\(plan.summary). Sync again and choose Continue in the confirmation dialog, or change the policy to Run Automatically.",
    "\\(deletedRefs.count) 个删除, \\(forcedUpdateRefs.count) 个强制更新": "\\(deletedRefs.count) deletions, \\(forcedUpdateRefs.count) forced updates",
    "本次将删除 \\(deletedRefs.count) 个 ref / 强制更新 \\(forcedUpdateRefs.count) 个 ref,是否继续?": "This will delete \\(deletedRefs.count) refs and force-update \\(forcedUpdateRefs.count) refs. Continue?",
    "我的仓库": "My Repositories",
    "组织: \\(org)": "Organization: \\(org)",
    "严格保护": "Strict Protection",
    "自动执行": "Run Automatically",
    "dry-run 检测到目标侧 ref 删除或强制更新时弹出确认,取消则阻断同步。": "Show a confirmation when the dry run detects ref deletions or forced updates on the target; canceling blocks the sync.",
    "检测到删除或强制更新也继续推送,适合临时镜像或已确认的目标仓库。": "Continue pushing when deletions or forced updates are detected. Suitable for temporary mirrors or confirmed target repositories.",
    "低电量模式已开启，计划同步已暂停": "Low Power Mode is on; scheduled sync is paused",
    "当前为蜂窝热点 / 昂贵网络，计划同步已暂停": "The current network is a cellular hotspot or an expensive network; scheduled sync is paused",
    "低电量模式且网络昂贵，计划同步已暂停": "Low Power Mode is on and the network is expensive; scheduled sync is paused",
    "手动": "Manual",
    "每 15 分钟": "Every 15 Minutes",
    "每 30 分钟": "Every 30 Minutes",
    "每小时": "Hourly",
    "每天": "Daily",
    "每周": "Weekly",
    "每月": "Monthly",
    "Gitea (Gitee 开源版)": "Gitea (the open-source edition of Gitee)",
    "创建 Personal Access Token(classic)，勾选 repo / read:org 权限。https://github.com/settings/tokens": "Create a Personal Access Token (classic) with the repo and read:org scopes. https://github.com/settings/tokens",
    "创建 Personal Access Token，勾选 read_api 权限。https://gitlab.com/-/user_settings/personal_access_tokens": "Create a Personal Access Token with the read_api scope. https://gitlab.com/-/user_settings/personal_access_tokens",
    "创建 Token,勾选 write:repository(创建仓库需要)。访问 <your-gitea-host>/user/settings/applications": "Create a token with the write:repository scope (required to create repositories). Visit <your-gitea-host>/user/settings/applications",
    "正在更新本地镜像...": "Updating local mirror...",
    "正在同步...": "Syncing...",
    "正在归档...": "Archiving...",
    "未标记": "Untagged",
    "\\(failures.count)/\\(results.count) 个目标失败（\\(succeededCount) 个成功）: \\(detail)": "\\(failures.count)/\\(results.count) targets failed (\\(succeededCount) succeeded): \\(detail)",
    "Token 有效, scopes = [\\(scopeList)]": "Token is valid, scopes = [\\(scopeList)]",
    "Token 有效, 但无法读取 scopes; 缺少必需权限: \\(missing)": "Token is valid, but its scopes could not be read; required scopes are missing: \\(missing)",
    "Token 有效, scopes = [\\(scopeList)]; 缺少必需权限: \\(missing)": "Token is valid, scopes = [\\(scopeList)]; required scopes are missing: \\(missing)",
    "在 Provider 上自动注册 webhook 需要额外的 admin:repo_hook 权限（超出日常镜像同步所需）。请仅在信任本机应用时授予。": "Automatically registering a webhook with the provider requires the additional admin:repo_hook scope, beyond what routine mirror sync needs. Grant it only if you trust this local app.",
    "在 GitLab 上自动注册 webhook 需要 api 权限。请仅在信任本机应用时授予。": "Automatically registering a webhook on GitLab requires the api scope. Grant it only if you trust this local app.",
    "在 Gitea 上自动注册 webhook 需要 write:repository 权限。请仅在信任本机应用时授予。": "Automatically registering a webhook on Gitea requires the write:repository scope. Grant it only if you trust this local app.",
    "浅克隆无法完整 push --mirror，将仅同步所选 ref，不构成完整备份。": "A shallow clone cannot perform a complete push --mirror. Only the selected refs will sync, so this is not a complete backup.",
    "已自定义 ref 过滤，将仅同步所选 ref，不构成完整备份。": "Custom ref filters are set. Only the selected refs will sync, so this is not a complete backup.",
    "同步失败：\\(repoName)": "Sync Failed: \\(repoName)",
    "连续失败 \\(consecutiveFailureCount) 次 — \\(message)": "\\(consecutiveFailureCount) consecutive failures — \\(message)",
    "专注模式结束后的同步摘要": "Sync Summary After Focus",
    "有仓库同步失败。": "Some repositories failed to sync.",
    " 等": " and others",
    "\\(items.count) 个仓库同步失败：\\(preview)\\(suffix)": "\\(items.count) repositories failed to sync: \\(preview)\\(suffix)",
    "分支 \\(branch) 内容分歧：src \\(srcCommitSHA.truncatingSHA) / dst \\(dstCommitSHA.truncatingSHA)": "Content divergence on branch \\(branch): src \\(srcCommitSHA.truncatingSHA) / dst \\(dstCommitSHA.truncatingSHA)",
    "源仓库缺少分支 \\(branch)": "Source repository is missing branch \\(branch)",
    "目标仓库缺少分支 \\(branch)": "Target repository is missing branch \\(branch)",
    "commit SHA 不一致，但未能取得两侧 tree hash": "Commit SHAs differ, but the tree hashes could not be obtained from both sides",
    "被动（不打断专注）": "Passive (Does Not Interrupt Focus)",
    "标准": "Standard",
    "时效性": "Time Sensitive",
    "仅在通知中心展示，不会打断当前专注模式。": "Show only in Notification Center without interrupting the current Focus.",
    "系统默认通知行为；专注模式开启时通常不会打断。": "Use the system's default notification behavior; notifications usually do not interrupt while Focus is on.",
    "允许在专注模式下以时效性通知打断（仍受系统设置约束）。": "Allow time-sensitive notifications to interrupt Focus, subject to system settings.",
    "Git 远程": "Git Remote",
    "文件系统归档": "Filesystem Archive",
    "仅本机 (127.0.0.1)": "Local Only (127.0.0.1)",
    "中继回落 (示意)": "Relay Fallback (Example)",
    "Webhook 仅监听本机回环地址。可用 curl 本地验证；外网需要开启下方暴露模式。": "The webhook listens only on the local loopback address. You can verify it locally with curl; external access requires an exposure mode below.",
    "需本机已安装 cloudflared。示例：cloudflared tunnel --url http://127.0.0.1:<port>，再把生成的 https 主机填入公共 Base URL。": "cloudflared must be installed locally. Example: cloudflared tunnel --url http://127.0.0.1:<port>, then enter the generated HTTPS host in Public Base URL.",
    "需本机已安装 tailscale 并启用 Funnel。示例：tailscale funnel <port>，再把 Funnel HTTPS 主机填入公共 Base URL。": "Tailscale must be installed locally with Funnel enabled. Example: tailscale funnel <port>, then enter the Funnel HTTPS host in Public Base URL.",
    "未来可由 Cloudflare Worker / GitHub App 长轮询中继到本机；本版本仅保留配置入口，不部署托管基础设施。": "A future Cloudflare Worker or GitHub App could relay to this Mac using long polling. This version provides configuration only and does not deploy hosted infrastructure.",

    # App, settings, status bar, and sidebar
    "同步": "Sync",
    "校验": "Verify",
    "启用同步失败通知": "Enable sync failure notifications",
    "首次失败时通知": "Notify on the first failure",
    "连续失败阈值：\\(store.preferences.consecutiveFailureThreshold) 次": "Consecutive failure threshold: \\(store.preferences.consecutiveFailureThreshold)",
    "通知级别": "Notification Level",
    "失败通知": "Failure Notifications",
    "仅在首次失败（可选）或连续失败达到阈值（及其倍数）时推送，避免短暂网络抖动刷屏。专注模式开启时会暂存，解除后发送聚合摘要。": "Notify only on the first failure (optional), or when consecutive failures reach the threshold and its multiples, to avoid alerts from brief network interruptions. Notifications are deferred while Focus is on and combined into a summary afterward.",
    "低电量模式时暂停计划同步": "Pause scheduled sync in Low Power Mode",
    "昂贵网络 / 热点时暂停计划同步": "Pause scheduled sync on expensive networks or hotspots",
    "计划同步暂停": "Scheduled Sync Pausing",
    "仅影响按频率自动触发的同步；手动同步与 webhook 即时同步不受影响。": "This affects only syncs triggered automatically by frequency. Manual sync and instant webhook sync are unaffected.",
    "启用本机 Webhook 监听": "Enable local webhook listener",
    "监听地址": "Listening Address",
    "正在绑定端口…": "Binding port…",
    "监听未运行": "Listener Not Running",
    "外网暴露": "External Access",
    "公共 Base URL（可选）": "Public Base URL (Optional)",
    "中继模式仅作配置示意：可用 Worker/GitHub App 长轮询转发到本机监听端口，本版本不部署托管服务。": "Relay mode is a configuration example only. A Worker or GitHub App can forward to the local listener using long polling; this version does not deploy a hosted service.",
    "Webhook 即时同步": "Instant Webhook Sync",
    "默认关闭。开启后在 127.0.0.1 随机端口接收 POST /hook/<id>；HMAC 密钥仅存 Keychain。Cloudflare / Tailscale 为可选运行时依赖，需你本机已安装。": "Off by default. When enabled, a random port on 127.0.0.1 accepts POST /hook/<id>. The HMAC secret is stored only in Keychain. Cloudflare and Tailscale are optional runtime dependencies that must be installed locally.",
    "恢复默认设置": "Restore Defaults",
    "已检测到 \\(tool)": "\\(tool) detected",
    "未检测到 \\(tool)（可手动安装后使用）": "\\(tool) not detected (you can install it manually)",
    "复制": "Copy",
    "校验频率": "Verification Frequency",
    "每次抽样 \\(appVM.verificationPreferences.sampleSize) 个仓库": "Sample \\(appVM.verificationPreferences.sampleSize) repositories each time",
    "下次抽样": "Next Sample",
    "备份可信度校验": "Backup Integrity Verification",
    "周期性对随机抽样的仓库执行 src/dst tip SHA 与 tree hash 比对。不一致时标记为内容分歧。": "Periodically compare the src/dst tip SHA and tree hash for a random sample of repositories. Mismatches are marked as content divergence.",
    "立即抽样校验": "Verify a Sample Now",
    "立即同步": "Sync Now",
    "全部同步": "Sync All",
    "打开主窗口": "Open Main Window",
    "搜索仓库": "Search Repositories",
    "暂无仓库": "No Repositories",
    "无匹配仓库": "No Matching Repositories",
    "关于 GitRelay": "About GitRelay",
    "设置": "Settings",
    "退出 GitRelay": "Quit GitRelay",
    "内容分歧": "Content divergence",
    "未同步": "Not Synced",
    "最近同步 \\(relative)": "Last synced \\(relative)",
    "今日": "Today",
    "成功": "Succeeded",
    "失败": "Failed",
    "未运行": "Not Run",
    "备份内容与源仓库不一致": "Backup content differs from the source repository",
    "所有": "All",
    "按标签分组": "Group by Tag",
    "显示": "Display",
    "手动添加": "Add Manually",
    "手动添加仓库": "Add a Repository Manually",
    "浏览远端仓库": "Browse Remote Repositories",
    "从 GitHub / GitLab 浏览并选择": "Browse and select from GitHub or GitLab",
    "删除仓库": "Delete Repository",
    "删除": "Delete",
    "取消": "Cancel",
    "确认删除「\\(name)」?本地镜像缓存也将被删除,此操作不可撤销。": "Delete “\\(name)”? The local mirror cache will also be deleted. This action cannot be undone.",
    "同步此组": "Sync This Group",
    "校验此组": "Verify This Group",
    "编辑组内所有仓库频率...": "Edit Frequency for All Repositories in Group...",
    "组操作": "Group Actions",
    "立即校验": "Verify Now",
    "编辑...": "Edit...",
    "删除...": "Delete...",
    "连续失败 \\(count) 次": "\\(count) consecutive failures",

    # Sheets
    "编辑组内同步频率": "Edit Group Sync Frequency",
    "将「\\(groupTitle)」组内 \\(repoCount) 个仓库的同步频率统一设为：": "Set the sync frequency for all \\(repoCount) repositories in “\\(groupTitle)” to:",
    "保存": "Save",
    "公钥预览": "Public Key Preview",
    "已复制到剪贴板": "Copied to Clipboard",
    "复制公钥": "Copy Public Key",
    "关闭": "Close",
    "类型": "Type",
    "启用": "Enabled",
    "目标 \\(index + 1)": "Target \\(index + 1)",
    "已禁用": "Disabled",
    "删除目标": "Delete Target",
    "选择…": "Choose…",
    "归档格式": "Archive Format",
    "文件名模板": "Filename Template",
    "可用占位符: {name}、{date} (yyyy-MM-dd)": "Available placeholders: {name}, {date} (yyyy-MM-dd)",
    "保留份数 (可选)": "Number to Keep (Optional)",
    "留空表示不自动清理旧归档。": "Leave blank to keep old archives indefinitely.",
    "选择": "Choose",
    "选择归档输出目录": "Choose an archive output directory",
    "输入标签后按回车添加": "Enter a tag and press Return to add it",
    "可用逗号或回车分隔多个标签；输入时会自动补全已有标签。": "Separate multiple tags with commas or Return. Existing tags are suggested as you type.",
    "移除标签": "Remove Tag",
    "SSH 密钥已生成": "SSH Key Generated",
    "将公钥添加到 \\(GitRemoteHost.sshKeysSettingsLabel(for: provider)) 后即可使用 SSH 认证。": "Add the public key to \\(GitRemoteHost.sshKeysSettingsLabel(for: provider)) to use SSH authentication.",
    "打开 \\(GitRemoteHost.sshKeysSettingsLabel(for: provider)) SSH 设置": "Open \\(GitRemoteHost.sshKeysSettingsLabel(for: provider)) SSH Settings",
    "完成": "Done",
    "生成 SSH 密钥": "Generate SSH Key",
    "私钥路径": "Private Key Path",
    "默认保存为 \\(SSHKeyGenerator.defaultDisplayPath)。公钥将写入同路径的 .pub 文件。": "The default path is \\(SSHKeyGenerator.defaultDisplayPath). The public key will be written to a .pub file at the same path.",
    "使用 passphrase 加密私钥": "Encrypt the private key with a passphrase",
    "生成": "Generate",
    "破坏性镜像推送确认": "Confirm Destructive Mirror Push",
    "将删除 \\(plan.deletedRefs.count) 个 ref": "Delete \\(plan.deletedRefs.count) refs",
    "将强制更新 \\(plan.forcedUpdateRefs.count) 个 ref": "Force-update \\(plan.forcedUpdateRefs.count) refs",
    "继续": "Continue",
    "同步频率": "Sync Frequency",
    "浏览并选择远端仓库": "Browse and Select Remote Repositories",
    "选择要镜像的仓库": "Select Repositories to Mirror",
    "配置目标仓库": "Configure Target Repositories",
    "正在创建目标仓库": "Creating Target Repositories",
    "执行结果": "Results",
    "处理中…": "Processing…",
    "GitLab Host(自建实例可选)": "GitLab Host (Self-Hosted Instance Optional)",
    "留空则使用 gitlab.com。会自动追加 /api/v4 路径。": "Leave blank to use gitlab.com. The /api/v4 path is appended automatically.",
    "仅用于拉取仓库列表,不用于 git 同步": "Used only to fetch the repository list, not for git sync",
    "保存到 Keychain(下次自动填充)": "Save to Keychain (Autofill Next Time)",
    "范围": "Scope",
    "选择范围": "Select Scope",
    "组织名称 (如 anthropic)": "Organization name (for example, anthropic)",
    "群组路径 (如 gitlab-org/charts)": "Group path (for example, gitlab-org/charts)",
    "搜索名称或描述": "Search Names or Descriptions",
    "全选当前": "Select All Visible",
    "清空": "Clear",
    "加载中...": "Loading...",
    "加载更多": "Load More",
    "已选择 \\(vm.selectedIDs.count) 个仓库": "\\(vm.selectedIDs.count) repositories selected",
    "源 URL 由所选仓库自动生成(按下方的源认证方式选择 SSH 或 HTTPS)": "Source URLs are generated from the selected repositories (choose SSH or HTTPS with the source authentication option below)",
    "源仓库认证(用于 git clone/fetch)": "Source Repository Authentication (for git clone/fetch)",
    "目标仓库": "Target Repository",
    "在目标端自动创建仓库 (Gitea)": "Automatically Create Repositories on the Target (Gitea)",
    "使用 Gitea API 按所选仓库批量创建; 名称冲突时复用已存在仓库。": "Use the Gitea API to create the selected repositories in a batch; reuse existing repositories when names conflict.",
    "目标仓库需要预先存在; 使用 {name} 模板生成 URL。": "Target repositories must already exist; URLs are generated with the {name} template.",
    "目标 URL 模板": "Target URL Template",
    "使用 {name} 作为仓库名占位符。": "Use {name} as the repository name placeholder.",
    "目标仓库认证(用于 git push)": "Target Repository Authentication (for git push)",
    "命名 & 频率": "Naming & Frequency",
    "名称前缀(可选)": "Name Prefix (Optional)",
    "预览(前 3 条)": "Preview (First 3)",
    "自动追加 /api/v1 路径。": "The /api/v1 path is appended automatically.",
    "需要 write:repository 权限": "Requires the write:repository scope",
    "命名空间": "Namespace",
    "位置": "Location",
    "将创建在当前 Token 所属用户名下。": "Repositories will be created under the username associated with the current token.",
    "组织名称": "Organization Name",
    "目标用户名(Token 需为管理员)": "Target Username (Token Must Be an Administrator)",
    "创建为 Private 仓库": "Create as Private Repositories",
    "正在处理 \\(vm.submitProgress) / \\(vm.submitTotal)": "Processing \\(vm.submitProgress) / \\(vm.submitTotal)",
    "成功 \\(succeeded)": "Succeeded \\(succeeded)",
    "复用 \\(existed)": "Reused \\(existed)",
    "失败 \\(failed)": "Failed \\(failed)",
    "详情": "Details",
    "上一步": "Back",
    "加载仓库": "Load Repositories",
    "下一步 (\\(vm.selectedIDs.count))": "Next (\\(vm.selectedIDs.count))",
    "创建并添加 \\(vm.selectedIDs.count) 个": "Create and Add \\(vm.selectedIDs.count)",
    "添加 \\(vm.selectedIDs.count) 个仓库": "Add \\(vm.selectedIDs.count) Repositories",
    "添加 \\(count) 个到同步列表": "Add \\(count) to Sync List",
    "远端已存在,将复用": "Remote already exists and will be reused",
    "创建成功": "Created Successfully",
    "\\(label) 认证": "\\(label) Authentication",
    "使用系统 SSH Agent(~/.ssh/config)": "Use System SSH Agent (~/.ssh/config)",
    "生成新密钥": "Generate New Key",
    "选择...": "Choose...",
    "查看密钥": "View Key",
    "Token 将加密存储在系统 Keychain 中": "The token will be encrypted in the system Keychain",
    "添加仓库": "Add Repository",
    "编辑仓库": "Edit Repository",
    "添加并开始同步": "Add and Start Syncing",
    "名称": "Name",
    "例如:my-project": "For example: my-project",
    "Source(源仓库)": "Source Repository",
    "添加目标": "Add Target",
    "Targets(目标仓库)": "Targets",
    "同一源仓库可镜像到多个目标；可选择 Git 远程或文件系统归档 (tar.gz / zip / git bundle)。禁用的目标在同步时跳过。": "A source repository can be mirrored to multiple targets. Choose a Git remote or filesystem archive (tar.gz, zip, or git bundle). Disabled targets are skipped during sync.",
    "标签": "Tags",
    "校验分支": "Verification Branch",
    "完整性校验比对 src/dst 上该分支的 tip 与 tree hash。": "Integrity verification compares this branch's tip and tree hash on src and dst.",
    "破坏性推送保护": "Destructive Push Protection",
    "策略": "Policy",
    "Release 镜像": "Release Mirroring",
    "镜像 Releases 及二进制 assets": "Mirror Releases and Binary Assets",
    "同步 git 仓库后，将源仓库 Release 的 tag/title/body 与 .dmg、.tar.gz 等附件增量复制到每个已启用目标。需要 GitHub/GitLab API Token。": "After syncing the git repository, incrementally copy source Release tags, titles, bodies, and attachments such as .dmg and .tar.gz files to each enabled target. A GitHub or GitLab API token is required.",
    "允许 Webhook 即时同步": "Allow Instant Webhook Sync",
    "路径：/hook/\\(editing.webhookPathID)": "Path: /hook/\\(editing.webhookPathID)",
    "复制 URL": "Copy URL",
    "HMAC 密钥已存入 Keychain": "HMAC secret saved in Keychain",
    "复制密钥": "Copy Secret",
    "保存后生成路径 /hook/<repo-id> 与 HMAC 密钥（写入 Keychain）。请同时在设置中启用本机监听。": "Saving generates a /hook/<repo-id> path and an HMAC secret stored in Keychain. Also enable the local listener in Settings.",
    "保存时尝试通过 GitHub API 注册 webhook": "Try to Register the Webhook Through the GitHub API When Saving",
    "GitHub Token（需 admin:repo_hook）": "GitHub Token (Requires admin:repo_hook)",
    "收到校验通过的 push 事件后立即同步，不受频率调度限制。需在「设置 → Webhook」启用本机监听；外网暴露使用 Cloudflare Tunnel / Tailscale Funnel（可选）。": "Sync immediately after receiving a verified push event, independent of the frequency schedule. Enable the local listener in Settings → Webhook. Cloudflare Tunnel or Tailscale Funnel can optionally provide external access.",
    "高级选项": "Advanced Options",
    "克隆深度（留空 = 全量历史）": "Clone Depth (Blank = Full History)",
    "Fetch refspecs（每行一条）": "Fetch Refspecs (One per Line)",
    "默认同步所有分支与 tag。可改为仅 main + v* tag，例如：\\n+refs/heads/main:refs/heads/main\\n+refs/tags/v*:refs/tags/v*": "By default, all branches and tags are synced. You can limit this to main and v* tags, for example:\\n+refs/heads/main:refs/heads/main\\n+refs/tags/v*:refs/tags/v*",
    "GitRelay 会先执行 dry-run。严格保护会在删除或强制更新前弹出确认弹窗;取消则阻断并记失败。自动执行保留传统 mirror 行为。": "GitRelay performs a dry run first. Strict Protection asks for confirmation before deletions or forced updates; canceling blocks the sync and records a failure. Run Automatically preserves traditional mirror behavior.",
    "Webhook 自动注册已跳过：未提供 GitHub Token。": "Automatic webhook registration was skipped because no GitHub token was provided.",
    "Webhook 自动注册已跳过：无法从源 URL 解析 owner/repo。": "Automatic webhook registration was skipped because owner/repo could not be parsed from the source URL.",
    "Webhook 自动注册已跳过：Token 缺少 admin:repo_hook。": "Automatic webhook registration was skipped because the token lacks admin:repo_hook.",
    "已在 GitHub 注册 webhook #\\(registration.id)。": "Registered webhook #\\(registration.id) on GitHub.",
    "Webhook 自动注册失败：\\(error.localizedDescription)": "Automatic webhook registration failed: \\(error.localizedDescription)",

    # Repository detail
    "近 30 天同步": "Syncs in the Last 30 Days",
    "\\(dateText): 无同步": "\\(dateText): No Syncs",
    "\\(dateText): 成功 \\(day.successes)，失败 \\(day.failures)": "\\(dateText): \\(day.successes) succeeded, \\(day.failures) failed",
    "近 30 天共成功 \\(successes) 次，失败 \\(failures) 次": "Over the last 30 days, \\(successes) succeeded and \\(failures) failed",
    "Release 镜像未启用": "Release Mirroring Is Disabled",
    "在编辑仓库中开启「镜像 Releases 及二进制 assets」，同步时会将 Release 附件复制到每个已启用目标。": "Enable “Mirror Releases and Binary Assets” when editing the repository to copy Release attachments to each enabled target during sync.",
    "尚无 Release 同步记录": "No Release Sync Records Yet",
    "执行一次同步后，此处会显示各目标的 Release 与 asset 进度。": "After a sync, the Release and asset progress for each target will appear here.",
    "上次 \\(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))": "Last \\(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))",
    "等待首次 Release 同步…": "Waiting for the First Release Sync…",
    "无附件": "No Attachments",
    "待同步": "Pending",
    "同步中": "Syncing",
    "已同步": "Synced",
    "部分完成": "Partially Completed",
    "备份内容可能已偏离源仓库": "Backup content may have diverged from the source repository",
    "最近校验：\\(lastVerifiedAt.formatted(.relative(presentation: .named)))": "Last verified: \\(lastVerifiedAt.formatted(.relative(presentation: .named)))",
    "同步日志": "Sync Log",
    "暂无记录": "No Records",
    "源": "Source",
    "正在同步...": "Syncing...",
    "src 领先 \\(n) 个 commit": "src is \\(n) commits ahead",
    "未知状态": "Unknown Status",
    "上次同步：\\(lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute()))": "Last synced: \\(lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute()))",
    "上次校验：\\(lastVerifiedAt.formatted(.relative(presentation: .named)))": "Last verified: \\(lastVerifiedAt.formatted(.relative(presentation: .named)))",
    "下次同步：\\(nextFireDate.formatted(.relative(presentation: .named)))(需 App 保持运行)": "Next sync: \\(nextFireDate.formatted(.relative(presentation: .named))) (the app must remain running)",
    "部分 ref 同步（非完整备份）": "Partial ref sync (not a complete backup)",
    "归档": "Archive",
    "上次同步失败": "Last Sync Failed",
    "连续失败 \\(consecutiveFailureCount) 次": "\\(consecutiveFailureCount) consecutive failures",
    "最近成功：\\(lastSuccessfulSyncedAt.formatted(.relative(presentation: .named)))": "Last success: \\(lastSuccessfulSyncedAt.formatted(.relative(presentation: .named)))",
    "重试": "Retry",
    "概览": "Overview",
    "详情页": "Detail Page",
    "未检测到分支(同步后可见)": "No Branches Detected (Visible After Sync)",
    "把任意 Git 仓库镜像同步到另一个仓库\\nGitLab → GitHub · Gitea · Gitee": "Mirror any Git repository to another repository\\nGitLab → GitHub · Gitea · Gitee",
    "添加第一个仓库": "Add Your First Repository",
    "检查更新": "Check for Updates",

    # View models and services
    "组织 / 群组": "Organization / Group",
    "当前用户": "Current User",
    "组织": "Organization",
    "管理员代建到用户": "Administrator Creates for User",
    "目标 API Host 无效": "The target API host is invalid",
    "加载仓库配置失败：\\(error.localizedDescription)": "Failed to load repository configuration: \\(error.localizedDescription)",
    "Webhook 监听启动失败：\\(error.localizedDescription)": "Failed to start the webhook listener: \\(error.localizedDescription)",
    "保存仓库配置失败:\\(error.localizedDescription)": "Failed to save repository configuration: \\(error.localizedDescription)",
    "请输入名称": "Enter a name",
    "请输入有效的 Git URL": "Enter a valid Git URL",
    "请选择归档目录": "Choose an archive directory",
    "保留份数须为正整数": "The number to keep must be a positive integer",
    "至少启用一个目标": "Enable at least one target",
    "深度须为正整数": "Depth must be a positive integer",
    "无法在 127.0.0.1 上绑定 webhook 监听端口": "Unable to bind the webhook listener port on 127.0.0.1",
    "完整性校验开始（分支: \\(branch)）...": "Integrity verification started (branch: \\(branch))...",
    "错误: \\(message)": "Error: \\(message)",
    "跳过 \\(enabledTargets.count - verifiableTargets.count) 个文件系统归档目标。": "Skipped \\(enabledTargets.count - verifiableTargets.count) filesystem archive targets.",
    "ls-remote 源仓库...": "Running ls-remote on source repository...",
    "(缺失)": "(missing)",
    "ls-remote 目标仓库...": "Running ls-remote on target repository...",
    "commit SHA 不一致，拉取对象以比较 tree hash...": "Commit SHAs differ; fetching objects to compare tree hashes...",
    "两侧 tip 一致 — 校验通过。": "Tips match — verification passed.",
    "commit SHA 不同但 tree hash 一致 — 校验通过。": "Commit SHAs differ but tree hashes match — verification passed.",
    "⚠ 检测到内容分歧: \\(detail.summary)": "⚠ Content divergence detected: \\(detail.summary)",
    "无法判定: \\(redacted)": "Inconclusive: \\(redacted)",
    "⚠ 检测到内容分歧: \\(summary)": "⚠ Content divergence detected: \\(summary)",
    "无法判定: \\(message)": "Inconclusive: \\(message)",
    "全部 \\(matchedCount) 个目标校验通过。": "All \\(matchedCount) targets passed verification.",
    "完整性校验已取消。": "Integrity verification canceled.",
    "\\(details.count) 个目标内容分歧: \\(details[0].summary)": "\\(details.count) targets have content divergence: \\(details[0].summary)",
    "拉取 \\(label) commit \\(commitSHA.truncatingSHA)...": "Fetching \\(label) commit \\(commitSHA.truncatingSHA)...",
    "管理员 → 用户: \\(user)": "Administrator → User: \\(user)",
    "鉴权失败(401)：\\($0)": "Authentication failed (401): \\($0)",
    "鉴权失败(401)": "Authentication failed (401)",
    "无权限(403)：\\($0)": "Permission denied (403): \\($0)",
    "无权限(403)": "Permission denied (403)",
    "参数错误：\\($0)": "Invalid parameters: \\($0)",
    "参数错误(422)": "Invalid parameters (422)",
    "网络错误：\\(e.localizedDescription)": "Network error: \\(e.localizedDescription)",
    "响应解析失败：\\(e.localizedDescription)": "Failed to parse response: \\(e.localizedDescription)",
    "鉴权失败(401)：请确认 Token 未过期且包含正确权限(GitHub 需 repo + read:org，GitLab 需 read_api)": "Authentication failed (401): Make sure the token has not expired and has the correct scopes (repo + read:org for GitHub, read_api for GitLab)",
    "\\(base)。服务器信息：\\($0)": "\\(base). Server message: \\($0)",
    "无权限或被限流(403)：\\($0)": "Permission denied or rate limited (403): \\($0)",
    "无权限或被限流(403)": "Permission denied or rate limited (403)",
    "资源不存在(404)：检查用户名或组织/群组名是否正确": "Resource not found (404): Check that the username, organization, or group name is correct",
    "网络请求失败：\\(e.localizedDescription)": "Network request failed: \\(e.localizedDescription)",
    "发生错误": "An Error Occurred",
    "确定": "OK",
}


def swift_files() -> list[Path]:
    """Return only production Swift files in the two requested source roots."""
    return sorted(path for root in SWIFT_ROOTS for path in root.rglob("*.swift"))


def is_persisted_frequency_case(path: Path, line: str) -> bool:
    return path.name in SPECIAL_FREQUENCY_FILES and bool(PERSISTED_CASE_RE.fullmatch(line.rstrip("\n")))


def chinese_literals(line: str) -> list[str]:
    return [
        match.group(1)
        for match in STRING_LITERAL_RE.finditer(line)
        if HAN_RE.search(match.group(1))
    ]


def catalog_format(value: str) -> str:
    """Convert balanced Swift interpolations to String Catalog placeholders."""
    result: list[str] = []
    index = 0
    while index < len(value):
        start = value.find(INTERPOLATION_START, index)
        if start < 0:
            result.append(value[index:])
            break
        result.append(value[index:start])
        cursor = start + len(INTERPOLATION_START)
        depth = 1
        in_string = False
        escaped = False
        while cursor < len(value) and depth:
            character = value[cursor]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            cursor += 1
        if depth:
            raise ValueError(f"Unbalanced Swift interpolation in {value!r}")
        result.append("%@")
        index = cursor
    return "".join(result)


def build_catalog() -> dict[str, object]:
    strings: dict[str, object] = {}
    origins: dict[str, str] = {}
    for chinese, english in TRANSLATIONS.items():
        key = catalog_format(english)
        zh_value = catalog_format(chinese)
        if key in strings:
            previous = origins[key]
            if previous != zh_value:
                raise ValueError(
                    f"Catalog key collision for {key!r}: {previous!r} and {zh_value!r}"
                )
            continue
        origins[key] = zh_value
        strings[key] = {
            "localizations": {
                "en": {
                    "stringUnit": {
                        "state": "translated",
                        "value": key,
                    }
                },
                "zh-Hans": {
                    "stringUnit": {
                        "state": "translated",
                        "value": zh_value,
                    }
                },
            }
        }
    return {
        "sourceLanguage": "en",
        "strings": dict(sorted(strings.items())),
        "version": "1.0",
    }


def info_plist_catalog() -> dict[str, object]:
    key = "NSFocusStatusUsageDescription"
    return {
        "sourceLanguage": "en",
        "strings": {
            key: {
                "localizations": {
                    "en": {
                        "stringUnit": {
                            "state": "translated",
                            "value": (
                                "GitRelay defers sync failure notifications while Focus is on, "
                                "then sends a combined summary when Focus ends."
                            ),
                        }
                    },
                    "zh-Hans": {
                        "stringUnit": {
                            "state": "translated",
                            "value": "GitRelay 会在专注模式开启时推迟同步失败通知，并在专注结束后发送聚合摘要。",
                        }
                    },
                }
            }
        },
        "version": "1.0",
    }


def write_json(path: Path, payload: dict[str, object]) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    files = swift_files()
    discovered: set[str] = set()
    protected: set[str] = set()

    for path in files:
        for line in path.read_text(encoding="utf-8").splitlines(keepends=True):
            literals = chinese_literals(line)
            discovered.update(literals)
            if is_persisted_frequency_case(path, line):
                protected.update(literals)

    missing = sorted(discovered - TRANSLATIONS.keys())
    if missing:
        formatted = "\n".join(f"  {value!r}" for value in missing)
        raise SystemExit(f"TRANSLATIONS is missing {len(missing)} literals:\n{formatted}")

    changed_files = 0
    replacement_count = 0
    for path in files:
        original = path.read_text(encoding="utf-8")
        output_lines: list[str] = []
        file_replacements = 0
        for line in original.splitlines(keepends=True):
            if is_persisted_frequency_case(path, line):
                output_lines.append(line)
                continue

            def replace_literal(match: re.Match[str]) -> str:
                nonlocal file_replacements
                content = match.group(1)
                translation = TRANSLATIONS.get(content)
                if translation is None:
                    return match.group(0)
                file_replacements += 1
                return f'"{translation}"'

            output_lines.append(STRING_LITERAL_RE.sub(replace_literal, line))

        updated = "".join(output_lines)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed_files += 1
            replacement_count += file_replacements

    catalog = build_catalog()
    write_json(ROOT / "gitrelay" / "Localizable.xcstrings", catalog)
    write_json(ROOT / "gitrelay" / "InfoPlist.xcstrings", info_plist_catalog())

    print(f"Swift files scanned: {len(files)}")
    print(f"Unique Chinese literals discovered: {len(discovered)}")
    print(f"Translation mappings: {len(TRANSLATIONS)}")
    print(f"Protected persistence values: {len(protected)}")
    print(f"Swift files changed: {changed_files}")
    print(f"Literal occurrences replaced: {replacement_count}")
    print(f"Localizable catalog entries: {len(catalog['strings'])}")
    print("String catalogs written: 2")


if __name__ == "__main__":
    main()
