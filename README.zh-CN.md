# GitRelay

为重要仓库提供持续、清晰、可验证的 Git 镜像保障。

GitRelay 是原生 macOS 镜像工作区。每个 Mirror 将一个源仓库、一个或多个目标、同步策略、健康状态和运行记录组合成单一产品对象。所有 Git 操作都在本机执行，包括 `git clone --mirror`、`git fetch --prune` 和 `git push --mirror`。

[English](./README.md)

## GitRelay 如何工作

- 智能视图直接呈现需要处理、正在运行、已暂停或带指定标签的 Mirror。
- Mirror 列表始终可见，支持搜索、比较和快速切换。
- 详情页由状态驱动，优先解释当前问题和下一步动作，再展示历史与诊断信息。
- “添加 Mirror”在同一流程中提供服务商浏览和手动 Git URL 两种入口。
- 连接账号和全局默认策略集中在系统原生设置窗口。
- 一个源可以同步到多个 Git 远端或文件系统归档。

GitRelay 支持 GitHub、GitLab、Gitea、Gitee、Bitbucket 和自托管 Git 服务，可使用 SSH Agent、指定 SSH 密钥或保存在 macOS 钥匙串中的 HTTPS Token。

## 核心能力

- 完整镜像分支和标签，并支持 prune
- 多目标独立结果与部分失败提示
- 基于 dry-run 确认的严格破坏性推送保护
- 相互独立的同步与校验计划
- 每个目标独立的新鲜度和完整性状态
- 搜索、标签、健康筛选和排序，面向 5 到 200 个 Mirror 的工作区
- 主窗口、菜单栏、小组件、快捷指令、通知和 CLI 共用同一 Mirror UUID
- Webhook 触发本机同步
- Git LFS 与 Release 资源镜像
- tar.gz、zip 和 Git bundle 文件归档
- 不包含 Token 明文的配置导入与导出
- 日志和持久化错误中的凭证遮蔽
- 英文与简体中文界面

## 本机执行边界

GitRelay 是本地优先工具，不是云端托管服务。计划同步和 Webhook 处理要求 Mac 处于唤醒状态，并且 GitRelay 进程可以运行。睡眠或中断后，应用会如实显示新鲜度和错过的任务，不会暗示具备持续在线的云端 SLA。手动同步、已有 Mirror、本地归档和 CLI 不依赖服务商浏览 API。

## 系统要求

- macOS 26.2 或更高版本
- Apple Silicon 或 Intel
- Git 位于 `/usr/bin/git`、`/usr/local/bin/git` 或 `/opt/homebrew/bin/git`

## 安装

### Homebrew

```bash
brew tap yangflow/tap
brew install --cask gitrelay
```

### 下载

从 [Releases](https://github.com/yangflow/gitrelay/releases) 下载最新 DMG，然后将 GitRelay 拖入“应用程序”。

当前社区构建使用临时签名。首次启动时请右键选择“打开”，或执行：

```bash
xattr -cr /Applications/GitRelay.app
```

### 从源码构建

```bash
git clone https://github.com/yangflow/gitrelay.git
cd gitrelay
open gitrelay.xcodeproj
```

选择 `gitrelay` Scheme，然后按 `Command-R`。

## 添加第一个 Mirror

1. 点击 Mirror 列表中的添加按钮。
2. 浏览已连接的服务商，或选择“输入 Git URL”。
3. 确认源仓库，并添加一个或多个目标。
4. 选择凭证和策略。新 Mirror 会继承“设置”中的默认值。
5. 添加 Mirror 并开始首次同步。

后续编辑继续使用同一界面，源、目标、凭证和策略不会分散到多个页面。

## CLI

应用包内包含 `GitRelay.app/Contents/MacOS/gitrelayctl`。

```bash
gitrelayctl list
gitrelayctl sync <mirror-uuid-or-unique-name>
gitrelayctl status [<mirror-uuid-or-unique-name>]
gitrelayctl logs <mirror-uuid-or-unique-name> [--tail N]
```

CLI 状态 JSON 使用 `mirrors`、`mirrorID` 和 `mirrorName`。显示名称必须唯一，UUID 查询始终稳定。

## 数据与隐私

| 数据 | 位置 |
|---|---|
| Mirror 计划 | `~/.local/share/gitrelay/mirrors.json` |
| 精简健康状态 | `~/.local/share/gitrelay/mirror-state.json` |
| 权威运行记录 | `~/.local/share/gitrelay/logs/` |
| Bare Mirror 缓存 | `~/.local/share/gitrelay/mirrors/<uuid>/` |
| 校验临时目录 | `~/.local/share/gitrelay/verify-scratch/` |
| HTTPS Token 和托管密钥 | macOS 钥匙串 |
| 小组件健康快照 | App Group `group.com.yangflow.gitrelay` |
| CLI 二进制 | `GitRelay.app/Contents/MacOS/gitrelayctl` |

Mirror 计划只包含仓库 URL 和策略，不保存 Token 明文或私钥内容。HTTPS Token 和托管密钥保存在 macOS 钥匙串中；导出的配置不包含密钥，错误与日志写入磁盘前也会遮蔽凭证。

## 开发检查

```bash
python3 scripts/check_string_catalog.py
python3 scripts/check_unlocalized_strings.py
xcodebuild test -project gitrelay.xcodeproj -scheme gitrelay \
  -destination 'platform=macOS' -testLanguage en -testRegion US \
  CODE_SIGNING_ALLOWED=NO
```

## 许可证

MIT，详见 [LICENSE](./LICENSE)。
