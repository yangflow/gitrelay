# GitRelay

在 Mac 上自动将任意 Git 仓库镜像同步到另一个仓库。

GitRelay 是一款原生 macOS 应用，用于管理多个 Git 托管平台之间的单向镜像同步。填写源仓库和一个或多个目标，选择同步频率，剩下的交给它：`git clone --mirror`、`git fetch --prune`、`git push --mirror`，安静地在后台运行，不打扰你的工作。

支持 GitLab、GitHub、Gitea、Gitee、Bitbucket 或自托管 Git 服务器的任意组合，内置 SSH Agent、SSH 密钥和 HTTPS Token 三种认证方式。界面语言跟随系统（英文 / 简体中文）。

[English](./README.md)

---

## 功能

- **多仓库侧边栏** — 在同一个窗口管理任意数量的仓库对；可按名称、URL、标签或同步状态搜索与过滤
- **1→N 扇出** — 一个源仓库，多个目标（Git 远端和/或文件系统归档）
- **全量镜像同步** — 所有分支和标签，单向 src → dst
- **标签 / 分组** — 给仓库打标签，并按标签做批量操作
- **破坏性推送保护** — mirror push 前先 dry-run，默认弹出确认阻断目标 ref 删除和强制更新
- **同步健康仪表盘** — 侧边栏/菜单栏汇总今日成功、失败、未运行；详情页含近期 sparkline
- **定时同步** — 每个仓库单独配置频率：手动、15 分钟、30 分钟、1 小时、1 天
- **静默时段** — 在本地时间窗口内跳过计划同步（手动同步仍可用）
- **灵活认证** — SSH Agent、SSH 密钥路径或 HTTPS Token（Token 存储在 macOS 钥匙串）
- **Token 权限校验** — 连接时检查 provider token scopes，权限不足时提前提示
- **内置 SSH 密钥生成** — 生成 ed25519 密钥并把公钥复制到剪贴板
- **多账户** — 每个 provider 可保存个人 / 工作（及自定义）标签，用于远程浏览
- **状态栏快捷操作** — 汇总状态、搜索，无需打开主窗口即可触发单仓同步
- **快捷指令 / App Intents** — 在快捷指令中调用 Sync / Sync All
- **gitrelayctl CLI** — 与 GUI 共用配置的无界面工具（`list` / `sync` / `status` / `logs`）；二进制位于 `GitRelay.app/Contents/MacOS/gitrelayctl`
- **Webhook 即时同步** — 推送事件触发同步，无需等待下一次计划
- **Release 资源镜像** — 同步 GitHub/GitLab Releases 及其二进制 assets
- **文件系统归档** — 将快照落到磁盘（tar.gz 或 git bundle）
- **浅克隆 / ref 过滤** — 为大仓库提供 depth 与 ref-glob 选项
- **组织自动订阅** — 监视组织/用户，发现新仓库时提示加入同步
- **Git LFS 对象** — 已安装 `git-lfs` 时自动随镜像同步
- **瞬时 git 重试** — 对网络抖动错误做指数退避重试
- **配置导出 / 导入** — 换机迁移仓库配置，不包含密钥与 Token
- **桌面 / 锁屏小组件** — 通过 App Group `group.com.yangflow.gitrelay` 一览同步健康度
- **Touch ID 门禁** — 显示 Token 明文或执行高危操作前需生物识别确认
- **LRU bare clone 清理** — 缓存配额，避免本地镜像无限增长
- **en-US + zh-Hans** — 界面语言跟随系统
- **同步日志** — 每次运行的详细日志，自动遮蔽凭证、自动分类错误
- **提交差值** — 推送前显示源仓库领先目标仓库的提交数量

---

## 系统要求

- macOS 14（Sonoma）或更高版本
- Apple Silicon 或 Intel
- 已安装 `git`（`/usr/bin/git`、`/usr/local/bin/git` 或 `/opt/homebrew/bin/git`）

---

## 安装

### Homebrew

```bash
brew tap yangflow/tap
brew install --cask gitrelay
```

### 下载 DMG

前往 [Releases](https://github.com/yangflow/gitrelay/releases) 下载最新版 `GitRelay-x.y.z.dmg`，打开后将 GitRelay 拖入 Applications 文件夹。

> 当前为未签名构建，首次启动请右键 → 打开，或执行：
> ```bash
> xattr -cr /Applications/GitRelay.app
> ```

### 从源码构建

```bash
git clone https://github.com/yangflow/gitrelay.git
cd gitrelay
open gitrelay.xcodeproj
```

选择 `gitrelay` Scheme，按 ⌘R。

---

## 使用方法

1. 点击工具栏的 **+** 或空状态页的按钮，添加一对仓库。
2. 填写名称、源仓库 URL，以及一个或多个目标 URL（或归档路径）。
3. 为两侧分别选择认证方式——SSH Agent 模式无需额外配置，只需系统已运行 `ssh-agent`。
4. 设置同步频率，点击 **添加并开始同步**。
5. 首次同步时 GitRelay 会将源仓库 bare clone 到本地，之后每次运行只做增量 fetch + push。

状态栏图标显示汇总状态：任意仓库同步失败时显示警告三角。脚本化可运行 `GitRelay.app/Contents/MacOS/gitrelayctl --help`。

---

## 数据位置

| 内容 | 路径 |
|------|------|
| 仓库配置 | `~/.local/share/gitrelay/repos.json`（应用与 `gitrelayctl` 共用） |
| 本地镜像克隆 | `~/.local/share/gitrelay/mirrors/<uuid>/` |
| HTTPS Token | macOS 钥匙串 |
| 小组件健康快照 | App Group `group.com.yangflow.gitrelay`（`widget-health-snapshot.json`） |
| gitrelayctl 二进制 | `GitRelay.app/Contents/MacOS/gitrelayctl` |

---

## 重新生成图标

图标 PNG 由 Swift 脚本生成并提交到仓库。如需修改配色后重新生成：

```bash
swift scripts/generate-icon.swift
```

图标为紫色圆角方块加白色 Y 形 Git 分支。其几何参数与
`GitRelayCore/Design/GitRelayMark.swift` 保持一致，菜单栏状态项也从同一份参数绘制
（单色模板，不带紫色底板）。修改时两处都要改；若不一致，`GitRelayMarkTests` 会失败。

---

## 参与贡献

欢迎提交 Issue 和 Pull Request，详见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

---

## 许可证

MIT — 详见 [LICENSE](./LICENSE)。
