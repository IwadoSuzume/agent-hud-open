# 任务：把 Agent HUD Open 移植到 Windows（全自动：实现 → 审核 → 测试 → 审批）

> 本文件是移植任务书的原文副本，供子 agent（port-reviewer / port-tester）与续跑的会话读取。

你是这个移植项目的唯一负责人，全程**无人值守**运行。不要向人类提问、不要等待确认；遇到不确定的选择，按本文的「决策原则」自行决定，并记录到 `docs/windows-port/DECISIONS.md`。直到所有里程碑完成，或剩余项都已在 `BLOCKERS.md` 中写明原因，才算结束。

> **如果你是一个新会话（或上下文被压缩过）**：先读 `docs/windows-port/PROGRESS.md`，从记录的位置继续，不要重做已通过审批的里程碑。

---

## 0. 项目事实（已核实，作为起点；动手前自己再确认一遍）

- 仓库：`https://github.com/jazzenchen/agent-hud-open`，Apache-2.0，Swift 6 / SwiftPM，`platforms: [.macOS(.v14)]`，**无任何第三方依赖**（这是项目规则，`make check` 会拦）。
- 约 413 个源文件、6.4 万行 Swift；4 个 target：
  | Target | 职责 | 平台依赖 |
  | --- | --- | --- |
  | `AgentHUDSupport` | `JSONValue`、`RecordCoding`（SHA-256 确定性 id、毫秒日期） | Foundation、**CryptoKit** |
  | `AgentHUDCore` | 17+ 个 agent 的 provider、用量账本（SQLite）、设置/用量 store、告警逻辑、面板布局、MCP server、client hooks | Foundation、**SQLite3、Darwin、os、Network、Security、CoreServices、CryptoKit**、Observation |
  | `AgentHUDDesktop` | 菜单栏、刘海岛/玻璃效果、悬浮面板、审批卡片、设置/统计窗口 | **SwiftUI、AppKit、QuartzCore、Carbon、ServiceManagement…**（纯 macOS） |
  | `AgentHUDOpenApp` | 可执行入口、启动参数、hook 命令分发 | AppKit |
- Core 中直接依赖 macOS 的集中点（不完全列表，自己用 grep 补全）：
  - `System/`：`AppSupport.swift`（`~/Library/Application Support`、`~/Library/Caches`）、`ChildProcess.swift`、`ProcessLines.swift`、`FileChangeMonitor.swift`（FSEvents）、`InstanceLock.swift`、`UnixSocket.swift`、`UnixSocketListener.swift`
  - 调用外部命令：`/bin/ps`、`/usr/sbin/lsof`、`/bin/sh`、`/bin/bash`、`/bin/zsh`
  - Keychain（`Security`）：Copilot 的 `gh:github.com`、`OpenAgentCredentials`
  - `Network` 框架：`ProviderHTTP`、`MCPAppChannel`、`PermissionRequests`、`CopilotClient`、`UnixSocketListener`
  - 各 provider 硬编码的 macOS 路径：`Library/Application Support/Claude`、`…/Cursor/User/globalStorage/state.vscdb`、`…/Grok Bot` 等
  - iTerm2 / 终端窗口跳转、Codex Desktop 的 `$CODEX_HOME/ipc/ipc.sock`、Antigravity 的 `ps`+`lsof` 端口发现
- 测试：`Tests/AgentHUDSupportTests`、`AgentHUDCoreTests`（大部分是纯逻辑，移植价值最高）、`AgentHUDDesktopTests`（UI，Windows 侧不可直接复用）。
- 设计不变量（`docs/architecture.md` → Design invariants），**移植后必须仍然成立**：整数精度、确定性 SHA-256 id（跨机器一致）、毫秒日期、测试不需要凭据和网络、单个来源失败不影响其他来源、单实例锁、不臆造生命周期、只显示观测到的配额行、vendor id 永不改变、不存储凭据和对话正文。
- 必读文档：`docs/architecture.md`、`docs/data-access.md`、`docs/providers.md`、`docs/usage-semantics.md`、`docs/session-lifecycle.md`、`docs/hud.md`、`docs/command-line.md`。

---

## 1. 目标与非目标

**目标**
1. Windows 10 22H2+ / Windows 11 x64（arm64 尽力而为）上可运行的 Agent HUD：托盘图标、屏幕顶部中央的「岛」（替代刘海）、可拖到任意屏幕边缘的 dock、悬浮面板（配额/余额/24h token/会话）、审批与提问卡片（Deny / Allow once / Always allow）、新回复提醒、设置窗口、统计窗口、`--demo` 示例数据模式、`--mcp` 服务、`--probe` 诊断。
2. 尽可能多的 provider 在 Windows 上真实可用，并有一张如实的支持矩阵。
3. **macOS 行为零回归**：所有现有 macOS 测试保持通过，macOS 产物不变。
4. 改动对上游友好：Windows 代码尽量放新文件，共享文件里只加最小的 `#if os(Windows)` 分支或平台抽象，方便日后 rebase 上游。

**非目标**
- 不重写 macOS UI，不改 macOS 上的视觉或行为。
- 不加 Agent HUD 自己的账号、云同步、遥测、自动更新服务。
- 不做代码签名、商店上架（产出未签名的便携包即可）。
- 不新增任何网络请求类型；Windows 版只发 macOS 版已经在发的那些请求。

---

## 2. 推荐架构（M0 中用证据验证；只有证伪后才可换方案）

**默认方案：Swift 内核跨平台 + Windows 原生 UI 外壳**

```
┌──────────────────────────────┐   命名管道 JSON-RPC（版本化）  ┌───────────────────────────────┐
│ agenthud-engine.exe (Swift)  │ ◀──────────────────────────▶ │ AgentHUD.exe  (C# .NET 8, WPF │
│  AgentHUDSupport + Core      │  \\.\pipe\agenthud-<SID>-ui   │  或 WinUI 3，M0 中定)          │
│  + Platform/Windows 实现     │                              │  托盘/岛/dock/面板/审批/设置/统计│
│  也承担 hook 命令与 --mcp    │                              └───────────────────────────────┘
└──────────────────────────────┘
```

理由：Core 有 6 万行经过测试的解析/计算/告警逻辑和大量规则，重写成本和回归风险都极高；Swift 官方提供 Windows 工具链，Foundation、Observation 可用；UI 层本来就是 AppKit/SwiftUI，无论如何都要重做，而 C#/WPF（或 WinUI 3）在 Windows 上做置顶透明窗口、托盘、Mica/Acrylic 最成熟。

**M0 必须做的可行性验证（spike），任一失败则写 ADR 评估备选**：
- AgentHUDSupport + AgentHUDCore 能否在 Windows 上用 Swift 工具链编译（先把平台相关文件用 `#if` 挡掉，看剩下的能否编译、测试能否跑）。
- SQLite：优先用 Windows SDK 自带的 `winsqlite3`（`winsqlite/winsqlite3.h` + `winsqlite3.lib`，系统自带 DLL），通过 module map/systemLibrary 暴露为与 macOS 同名或同 API 的模块；不行再考虑把 SQLite amalgamation（public domain）作为本地 C target 放进仓库并在 `THIRD_PARTY_NOTICES.txt` 和边界检查里登记。
- SHA-256：Windows 上没有 CryptoKit。用 `#if canImport(CryptoKit)` 保留 macOS 路径，Windows 上用 CNG（`BCrypt*`，通过 WinSDK）或纯 Swift 实现，**必须用 NIST 测试向量 + 跨平台金样本验证结果完全一致**。
- 备选方案（仅在证伪后）：B. 全部用 Swift + swift-winrt/WinUI；C. 整体用 Rust/Tauri 或 C# 重写 Core。必须在 ADR 中给出具体证据（编译错误、缺失 API、工作量估算），不能凭感觉换。

---

## 3. 平台映射表（实现时逐项落实，并补全你发现的新项）

| macOS | Windows 对应 |
| --- | --- |
| 刘海岛 / 无刘海屏幕的 HUD | 顶部居中置顶无边框窗口（`WS_EX_TOOLWINDOW \| WS_EX_NOACTIVATE \| WS_EX_TOPMOST`，收起时鼠标穿透 `WS_EX_TRANSPARENT`），每块显示器独立；dock 可拖到四边 |
| 菜单栏图标与菜单 | 系统托盘图标 + 自绘弹出菜单 |
| Liquid Glass / 毛玻璃 | Win11：`DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)` Mica/Acrylic；Win10：纯色回退 |
| 减少透明度 | 注册表 `HKCU\…\Themes\Personalize\EnableTransparency` |
| 浅色/深色 | `AppsUseLightTheme`，并监听 `WM_SETTINGCHANGE` |
| `~/Library/Application Support/Agent HUD Open` | `%APPDATA%\Agent HUD Open` |
| `~/Library/Caches/app.agenthud/instance.lock` | `%LOCALAPPDATA%\app.agenthud\instance.lock`（+ 命名 Mutex `Local\app.agenthud.instance`） |
| UserDefaults | `%APPDATA%\Agent HUD Open\settings.json`（原子写），demo/snapshot 用独立文件 |
| FSEvents（`FileChangeMonitor`） | `ReadDirectoryChangesW`（递归、处理缓冲区溢出 = 「事件丢失」，触发全量读，与 architecture.md 的语义一致） |
| `realpath` | `GetFinalPathNameByHandleW`，路径比较大小写不敏感 |
| Unix socket（hook 回传、`mcp.sock`） | 命名管道，**DACL 只允许当前用户 SID**；保持「一次请求 = 一条消息，发送方关闭写端结束」的语义 |
| `ps` | `CreateToolhelp32Snapshot` / `NtQueryInformationProcess` 读命令行与启动时间 |
| `lsof` 查监听端口 | `GetExtendedTcpTable`（按 PID 过滤 LISTEN） |
| Keychain `gh:github.com` | Windows Credential Manager `CredReadW("gh:github.com")`（核实 gh 在 Windows 的实际存储方式） |
| `os.Logger` | 轻量日志 shim（OutputDebugString + 可选文件），不得记录凭据 |
| `Network` 框架 HTTP | `URLSession`（FoundationNetworking）或 WinHTTP；保持超时与请求间隔语义 |
| 登录项（ServiceManagement） | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| 全局热键（Carbon） | `RegisterHotKey` |
| iTerm2/终端会话跳转 | Windows Terminal / VS Code / 进程主窗口 `SetForegroundWindow`（遵守前台锁规则）；做不到的就不显示跳转按钮 |
| `/bin/sh -c` 执行 | 直接 `CreateProcessW` 传参数组，**禁止**拼接 shell 字符串 |

**Provider 路径**：逐个 provider 研究其 Windows 版的数据位置（例如 Claude Code `%USERPROFILE%\.claude`、Codex `%USERPROFILE%\.codex` / `CODEX_HOME`、Cursor `%APPDATA%\Cursor\User\globalStorage\state.vscdb`、Claude Desktop `%APPDATA%\Claude` ……以官方文档或客户端源码为准）。**查不到确切依据的，标记为「Windows 暂不支持」并在设置里如实显示，不要猜路径**（符合 Observed rows only 不变量）。结果写入 `docs/windows-port/SUPPORT_MATRIX.md`：每个 client × {会话/用量、配额查询、审批 hook、完成提醒、会话跳转} 的状态和依据链接。

**Client hooks（重点风险）**：Claude Code 等客户端会以命令行方式调用本程序的可执行文件。Windows 上要核实各客户端执行 hook 的 shell（cmd / PowerShell / Git Bash），生成的命令要正确处理带空格和非 ASCII 的路径、`.exe` 后缀、反斜杠；hook 进程必须是 console 子系统的 `agenthud-engine.exe`，启动要快，且不能弹出黑窗口影响用户。安装器只改自己的条目，原样保留其他 hook，保留文件权限，无法识别的格式拒绝改写（与 macOS 相同规则）。

---

## 4. 里程碑（按顺序；每个都要走完第 5 节的审批循环）

- **M0 侦察与决策**（不写产品代码）：通读必读文档；生成 `PORTING_PLAN.md`（文件级清单：每个 macOS 依赖点 → 处理方式 → 所属里程碑）；完成第 2 节的 spike；写 ADR-001（总体架构）、ADR-002（UI 技术：WPF vs WinUI 3，用置顶透明窗口、托盘、Mica、DPI/多显示器、打包体积等维度打分）、ADR-003（SQLite 方案）、ADR-004（SHA-256 方案）。
- **M1 Windows CI 骨架**：新增 `.github/workflows/windows.yml`（`windows-latest`），自己查当前推荐的 Swift for Windows 安装方式与稳定版本并固定版本号，加缓存；先让「空 Core 编译」跑绿。**不修改现有 macOS 工作流的行为。**
- **M2 Support 跨平台**：SHA-256 替换路径 + NIST 向量测试 + 金样本测试（见 G4）。`AgentHUDSupportTests` 在 Windows 全绿。
- **M3 Core 平台抽象层**：新建 `Sources/AgentHUDCore/Platform/`（协议 + `Darwin`/`Windows` 实现），把 `System/` 中的路径、进程、端口、文件监视、IPC、实例锁、日志、凭据读取迁到抽象之后；macOS 实现应是原代码原样搬移。Core 在 Windows 编译通过，`AgentHUDCoreTests` 在 Windows 上跑通，仅允许有记录的跳过（见 G3）。
- **M4 Providers**：按支持矩阵逐个适配，每个 provider 用临时目录里的假数据（fixture）测试，不读真实用户目录。
- **M5 Hooks 与 MCP**：hook 命令生成与安装、`HookEntry.handle` 分发、`--mcp` stdio 服务、命名管道通道；用临时 `USERPROFILE`/`APPDATA` 做端到端测试（启动引擎 → 模拟客户端调用 hook → 引擎收到请求 → 模拟 UI 回答 → hook 进程拿到答复并以正确退出码结束）。
- **M6 引擎可执行与 UI 协议**：新增 executable target `AgentHUDEngine`（Windows 专用，不影响 macOS 产物）；定义版本化协议 `docs/windows-port/PROTOCOL.md` + JSON Schema：推送 `UsageReport`/告警/审批请求，接收设置变更/审批答复/刷新请求；本地化字符串由 Core 提供给 UI（复用现有中英文案，不另起炉灶）。协议契约测试两端都要跑（同一批 fixture）。
- **M7 Windows UI 外壳**：在 `windows/` 目录下实现（托盘、岛、dock、面板、审批卡片、提醒、设置、统计、`--demo`）；Per-Monitor-V2 DPI、多显示器、显示器热插拔、全屏应用时不遮挡（可选：全屏时自动隐藏）。UI 只做展示与交互，**所有业务判断留在 Core**（告警级别、配额计算、会话阶段等不得在 C# 里重新实现）。
- **M8 打包**：便携 zip（引擎 + UI + 资源 + LICENSE + THIRD_PARTY_NOTICES.txt），`scripts/build-windows.ps1` 一键构建；可选 Inno Setup/MSIX 脚本但不签名。CI 产出构建物仅作为 workflow artifact，不发布 release。
- **M9 收尾**：全量 gate、文档（`README` 增加 Windows 小节、`docs/windows.md`、`CHANGELOG` 条目）、最终报告 `docs/windows-port/FINAL_REPORT.md`（完成项、支持矩阵摘要、已知问题、BLOCKERS、如何构建运行）。

---

## 5. 自动化审批循环（每个里程碑都执行）

先在仓库里创建两个子 agent 定义（`.claude/agents/`），让审核与测试在**独立上下文**里进行，避免自己给自己打分：

- `port-reviewer.md`：只读工具。输入是本里程碑的 diff（`git diff <里程碑起点>...HEAD`）和本文件。按第 6 节检查清单逐条审查，输出 `VERDICT: APPROVE` 或 `VERDICT: CHANGES_REQUESTED`，每条问题标 `BLOCKING`/`NON_BLOCKING`，附文件:行号与修复建议。它不能修改代码。
- `port-tester.md`：可运行命令。执行第 6 节全部适用的 gate，输出每个 gate 的 PASS/FAIL、命令、关键日志摘要、跳过的测试清单。它不能修改源代码（可以写测试报告）。

**循环**：
1. 实现（你自己）→ 本地自检 → 提交到分支 `windows-port`（小步提交，信息说明意图）。
2. 调用 `port-tester`。有 FAIL → 回到 1 修复。
3. 调用 `port-reviewer`。有 BLOCKING → 回到 1 修复。NON_BLOCKING 可以修，也可以记录到 `PROGRESS.md` 的待办。
4. **审批规则（全部满足才算通过）**：所有适用 gate PASS；reviewer `APPROVE` 且无 BLOCKING；`PROGRESS.md`、`DECISIONS.md` 已更新；macOS 非回归 gate 已验证（见 G1）。通过后打标签 `port-M<n>-approved`，在 `PROGRESS.md` 记录时间、提交号、gate 结果摘要。
5. 同一里程碑最多 **4 轮** 审核/测试循环；仍未通过则：把剩余问题写进 `BLOCKERS.md`（现象、已尝试的办法、建议），在不破坏已通过部分的前提下继续后续里程碑；被阻塞项依赖的后续工作同样标记。

---

## 6. Gate 与审查清单

**G1 macOS 非回归**：如果当前机器是 macOS，跑 `make check` 和 `swift test`；否则通过推送分支触发现有的 macOS GitHub Actions 工作流并用 `gh run watch`/`gh run view` 读取结果。Core/Support 的任何改动都必须过这一关。
**G2 Windows 构建**：Windows 上 `swift build -c release` 构建 Support、Core、Engine；UI 用 `dotnet build -c Release`，警告不得新增。若当前机器不是 Windows，以 `windows.yml` CI 结果为准（同样用 `gh` 读取）。
**G3 Windows 测试**：`swift test`（Support + Core 测试）在 Windows 通过。仅限 macOS 的测试用 `#if os(macOS)` 跳过，且必须列入 `docs/windows-port/SKIPPED_TESTS.md`（测试名 + 原因 + 是否有 Windows 等价测试）；未登记的跳过视为失败。Platform/Windows 每个实现都要有自己的测试。
**G4 跨平台确定性**：在 macOS 上生成金样本（若干 `RecordCoding` 编码结果、记录 id、SHA-256 值、毫秒日期往返），提交为 fixture；Windows 测试必须逐字节一致。
**G5 UI**：`dotnet test`（视图模型与协议契约测试）；冒烟测试：以 `--demo` 启动，用快照模式（实现一个类似 macOS `--snapshot` 的离屏渲染导出 PNG）检查岛、面板、审批卡片、设置窗口图像非空且尺寸正确；进程 30 秒内无崩溃、退出码 0。
**G6 边界与静态检查**：扩展 `scripts/check-source-boundaries.py` 覆盖 `windows/` 目录：无密钥样式字符串、无签名材料、依赖白名单（.NET 侧只允许必要且许可证兼容的包，每个都在 DECISIONS.md 记录理由并写入 `THIRD_PARTY_NOTICES.txt`）；Swift 6 严格并发模式保持开启。
**G7 安全与隐私审查（reviewer 必查）**：
- 凭据只在内存中用于对应 provider 请求，不写日志、不落盘、不进报告；测试中不读真实凭据。
- 命名管道与锁文件仅当前用户可访问；不监听任何网络端口。
- 不拼 shell 字符串；外部命令全部参数数组方式调用。
- hook 安装器不破坏用户其他配置；关闭 Client hooks 能干净移除；移除不会创建原本不存在的文件。
- 审批请求无人处理时按原规则 10 分钟后退回客户端自身提示，HUD 永远不替用户作答。
- 路径：空格、中文、超过 MAX_PATH、OneDrive 重定向的文档目录、大小写差异。
**G8 文档**：新增/改动的行为在对应文档中写明，支持矩阵与实现一致。

**Reviewer 额外检查**：是否把业务逻辑复制到了 UI 层；是否改动了 macOS 行为；共享文件里的改动是否最小；是否有猜测出来的路径或接口；错误是否被吞掉；是否违反 architecture.md 的任何规则。

---

## 7. 决策原则（无人可问时按此顺序取舍）

1. 安全与隐私 > 正确性 > macOS 零回归 > 与上游可合并性 > Windows 功能完整度 > 视觉还原度。
2. 不确定某个客户端在 Windows 上的行为时：先查官方文档/源码；查不到就不支持并如实显示，绝不臆测。
3. 与 macOS 文档语义保持一致；必须不同时（例如没有刘海），在 `docs/windows.md` 写清差异。
4. 能用系统自带能力就不加依赖；必须加依赖时选许可证兼容、维护活跃、体积小的，并记录。
5. 每个重要选择写一条 ADR（背景、选项、决定、后果）。

---

## 8. 运行规则

- 只在 `windows-port` 分支工作；不推送 `main`，不 force-push，不向上游开 PR、不发 issue、不发布 release。可以推送 `windows-port` 分支以触发 CI。
- 不修改用户真实的 `~/.claude`、`~/.codex` 等客户端配置；所有涉及这些目录的测试都用临时目录覆盖环境变量。
- 保持 Apache-2.0 许可证、`LICENSE`、`THIRD_PARTY_NOTICES.txt`（根目录与资源包中的副本保持逐字节一致）、Clawd 精灵图与 LobeIcons 的原有署名；在 README 中说明这是社区 Windows 移植，不冒充官方发行。
- 长任务用后台进程 + 轮询，别让单条命令卡死会话；CI 等待用 `gh run watch`。
- 每完成一步就更新 `PROGRESS.md`（当前里程碑、已完成、下一步、已知问题），保证任何时候中断都能续上。
- 最终输出：`FINAL_REPORT.md` 的路径、分支名、最后一个通过审批的标签、构建与运行方法、BLOCKERS 摘要。
