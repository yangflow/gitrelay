# GitRelay

在 Mac 上自动将任意 Git 仓库镜像同步到另一个仓库。

GitRelay 是一款原生 macOS 应用，用于管理多个 Git 托管平台之间的单向镜像同步。填写源仓库和目标仓库，选择同步频率，剩下的交给它：`git clone --mirror`、`git fetch --prune`、`git push --mirror`，安静地在后台运行，不打扰你的工作。

支持 GitLab、GitHub、Gitea、Gitee、Bitbucket 或自托管 Git 服务器的任意组合，内置 SSH Agent、SSH 密钥和 HTTPS Token 三种认证方式。界面语言跟随系统（英文 / 简体中文）。

[English](./README.md)

---

## 功能

- **多仓库侧边栏** — 在同一个窗口管理任意数量的仓库对
- **全量镜像同步** — 所有分支和标签，单向 src → dst
- **破坏性推送保护** — mirror push 前先 dry-run，默认弹出确认阻断目标 ref 删除和强制更新
- **同步健康仪表盘** — 侧边栏/菜单栏显示「最近同步」时间与连续失败徽标，汇总今日成功、失败、未运行；详情页含近 30 天 sparkline
- **定时同步** — 每个仓库单独配置频率：手动、15 分钟、30 分钟、1 小时、1 天
- **灵活认证** — SSH Agent、SSH 密钥路径或 HTTPS Token（Token 存储在 macOS 钥匙串）
- **状态栏快捷操作** — 一眼看清同步状态，无需打开主窗口即可触发同步
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
2. 填写名称、源仓库 URL 和目标仓库 URL。
3. 为两侧分别选择认证方式——SSH Agent 模式无需额外配置，只需系统已运行 `ssh-agent`。
4. 设置同步频率，点击 **添加并开始同步**。
5. 首次同步时 GitRelay 会将源仓库 bare clone 到本地，之后每次运行只做增量 fetch + push。

状态栏图标显示汇总状态：任意仓库同步失败时显示警告三角。

---

## 数据位置

| 内容 | 路径 |
|------|------|
| 仓库配置 | `~/.local/share/gitrelay/repos.json` |
| 本地镜像克隆 | `~/.local/share/gitrelay/mirrors/<uuid>/` |
| HTTPS Token | macOS 钥匙串 |

---

## 重新生成图标

图标 PNG 由 Swift 脚本生成并提交到仓库。如需修改配色后重新生成：

```bash
swift scripts/generate-icon.swift
```

---

## 参与贡献

欢迎提交 Issue 和 Pull Request，详见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

---

## 许可证

MIT — 详见 [LICENSE](./LICENSE)。
