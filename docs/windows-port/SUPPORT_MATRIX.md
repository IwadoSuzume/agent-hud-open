# Windows support matrix

What the Windows build does for each client, and the source each Windows-specific fact rests on (TASK.md §3, §7.2).
A fact without a source is not used: the client, or that part of it, is **not supported on Windows**, Core treats it
as absent (`PlatformSupport`, so it is neither read nor given hooks), and Settings says so (M7).

Status: ✅ supported, tested on Windows with fixtures · 🔶 not supported on Windows (reason given) · ⏳ planned, with
its milestone. State at M4 (2026-10-17).

Columns: **Sessions/usage** (local records → sessions, tokens, ledger), **Quota** (account quota or balance request,
the same requests the macOS build makes, over WinHTTP: D-014), **Approvals** (permission hook or native requests),
**Completion** (stop/completion hook or observer), **Jump** (reveal the session's terminal or window).

| Client | Windows location (default; override) | Sessions/usage | Quota | Approvals | Completion | Jump |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code | `%USERPROFILE%\.claude`, `.claude.json`; `CLAUDE_CONFIG_DIR` | ✅ | ✅ engine `get_usage` | ⏳ M5 | ⏳ M5 | 🔶 ¹ |
| Claude desktop app (its Code sessions and its downloaded engine) | — | 🔶 ² | — | — | — | 🔶 |
| Codex | `%USERPROFILE%\.codex`; `CODEX_HOME` | ✅ | ✅ `app-server` over stdio | ⏳ M5 | ⏳ M5 | 🔶 ¹ |
| Codex desktop app (IPC, daemon origins) | — | 🔶 ³ | 🔶 ³ | 🔶 ³ | — | 🔶 |
| GitHub Copilot CLI | `%USERPROFILE%\.copilot`; `COPILOT_HOME` | ✅ | ✅ GitHub CLI sign-in | ⏳ M5 | ⏳ M5 | 🔶 ¹ |
| Cursor | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` (the agent CLI's `~/.cursor` chat names: 🔶 ⁸) | ✅ | ✅ | — | 🔶 ⁹ | 🔶 ¹ |
| OpenCode (+ OpenCode Go quota) | data `%USERPROFILE%\.local\share\opencode`, config `%USERPROFILE%\.config\opencode\opencode.json(c)`; `XDG_DATA_HOME`, `XDG_CONFIG_HOME` | ✅ | ✅ | — | ✅ plugin (Node) | 🔶 ¹ |
| Pi | `%USERPROFILE%\.pi\agent`; `PI_CODING_AGENT_DIR` | ✅ | — | — | ✅ extension (Node) | 🔶 ¹ |
| Kimi Code / GLM (quota from client configs) | Kimi `%USERPROFILE%\.kimi-code`; `KIMI_CODE_HOME` (the older `~/.kimi` is not read) | ✅ | ✅ | — | — | 🔶 ¹ |
| Qwen Code | `%USERPROFILE%\.qwen`; `QWEN_HOME` | ✅ | — | — | ⏳ M5 | 🔶 ¹ |
| CodeBuddy Code | `%USERPROFILE%\.codebuddy`; `CODEBUDDY_CONFIG_DIR` | ✅ | — | — | ⏳ M5 | 🔶 ¹ |
| OpenClaw | `%USERPROFILE%\.openclaw`; `OPENCLAW_STATE_DIR` | ✅ | — | — | — | 🔶 ¹ |
| Hermes Agent | `%USERPROFILE%\.hermes`; `HERMES_HOME` | ✅ ⁴ | — | — | — | 🔶 ¹ |
| Grok CLI | `%USERPROFILE%\.grok`; `GROK_HOME` | ✅ | ✅ local quota cache | — | — | 🔶 ¹ |
| Grok Bot (desktop) | — | 🔶 ² | 🔶 ² | — | — | 🔶 |
| DeepSeek Harness CLI (`dsh`) | `%USERPROFILE%\.dsh`; `DSH_HOME`; package from npm's global folder | ✅ (Node ≥ 22.19 for compressed logs) | ✅ balance | ⏳ M5 ⁵ | — | 🔶 ¹ |
| DeepSeek Harness desktop app | — | 🔶 ² | 🔶 ² | 🔶 ² | — | 🔶 |
| Antigravity / agy | — | 🔶 ⁶ | 🔶 ⁶ | 🔶 ⁶ | 🔶 ⁶ | 🔶 |
| Qoder, Qoder CN, QoderWork (approvals only) | `%USERPROFILE%\.qoder`, `.qoder-cn`, `.qoderwork` to be sourced | — | — | ⏳ M5 (unsupported unless sourced) | — | 🔶 |
| ZCode | — | 🔶 ⁷ | — | — | — | 🔶 |
| WorkBuddy | — | 🔶 ⁷ | — | — | — | 🔶 |

1. Jump reveals the session's terminal tab or window through macOS automation (AppleScript, Accessibility); Windows
   has no equivalent for other applications' tabs. The session list still shows the project and client.
2. No source gives the desktop app's data folder on Windows; the macOS folders (`~/Library/Application Support/…`,
   `/Applications`, `~/Applications/….app`) are never looked for there: `PlatformSupport.supportsDesktopApps` is false
   for Claude's desktop app (its engine and its Code sessions), the Codex app, Grok Bot (data, sessions, quota cache,
   routine runs) and DeepSeek Harness's app (D-036; D-019: `/Applications` would name a folder at the current drive's
   root that any user may create).
3. The Codex desktop app's IPC socket and daemon are macOS mechanisms; `CodexDesktopIPC` is always unavailable on
   Windows (D-006, Platform/Windows/CodexDesktopIPC+Windows.swift).
4. Hermes Agent calls its native Windows build an early beta.
5. The question observer works over WebSocket; swift-corelibs' WebSocket ends a quiet stream on Windows, so M5 gives it
   a WinHTTP WebSocket (SKIPPED_TESTS.md).
6. Only community reports place Antigravity's files and processes on Windows (`%LOCALAPPDATA%\Programs\Antigravity`,
   `language_server_windows_x64.exe`, `%USERPROFILE%\.gemini\antigravity`); no Google documentation was found.
   `PlatformSupport.supports(.antigravity)` is false: no folder is read and no process is listed.
7. No Windows location was found for these clients' data. `PlatformSupport.supports` is false for them: their folders
   are neither read nor watched, no quota is asked, no hook is installed, and WorkBuddy's `models.json` is not read
   for a GLM key (D-036).
8. Cursor's agent CLI keeps its chats and ACP sessions in `~/.cursor` on macOS; no source places them on Windows, so
   session names there come from the editor's database alone.
9. No source gives the shell Cursor runs a hook's command in on Windows (its docs name none; D-037, M5).

## Executables (D-019)

The Windows build starts a client's program only when it is an absolute drive or UNC path to an existing PE image,
never a batch file (`.cmd`/`.bat`, npm's shims) and never a POSIX path (`/opt/homebrew/bin/…`), which would name a
folder at the current drive's root. `PATH` is read without regard to the variable's case, split on `;`, relative
entries skipped, each entry tried with `name.exe`. Per client:

| Client | Programs looked for, in order |
| --- | --- |
| Claude Code | `%USERPROFILE%\.local\bin\claude.exe`, the native installer's versions under `%USERPROFILE%\.local\share\claude\versions`, `claude.exe` on `PATH` |
| Codex | npm's native engine: `%APPDATA%\npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-{x64,arm64}\vendor\<triple>\bin\codex.exe`, the same platform package hoisted to `%APPDATA%\npm\node_modules\@openai\…`, `…\@openai\codex\vendor\<triple>\bin\codex.exe`; then `codex.exe` on `PATH` |
| Node.js (DeepSeek, plugin tests) | `node.exe` on `PATH` |

A child's `PATH` is passed on as this process's, never extended with macOS folders; a child given an environment of its
own keeps `SystemRoot`, `windir` and `SystemDrive` (D-035).

## Sources

### Claude Code

- Config and records: `%USERPROFILE%\.claude` and `%USERPROFILE%\.claude.json` — Claude Code docs, *Advanced setup →
  Remove configuration files → Windows PowerShell* (https://code.claude.com/docs/en/setup).
- Engine: native installer `%USERPROFILE%\.local\bin\claude.exe`, versions under `%USERPROFILE%\.local\share\claude`
  (same page, *Uninstall a native installation → Windows PowerShell*); WinGet package `Anthropic.ClaudeCode`; npm
  installs the same native binary through `@anthropic-ai/claude-code-win32-x64` (same page, *Install with npm*).
  Windows binaries are Authenticode-signed by "Anthropic, PBC".
- Hooks: a command hook may be given in exec form, `command` plus `args`, which runs no shell; on Windows `command`
  must be a real `.exe`, not a `.cmd`/`.bat` shim; without `args` the hook runs in Git Bash when installed, else
  PowerShell (`shell` field) — Claude Code docs, *Hooks* (https://code.claude.com/docs/en/hooks).

### Codex

- Data: `home_dir()` joined with `.codex`, `CODEX_HOME` first — openai/codex, `codex-rs/utils/home-dir`
  (`find_codex_home`); `home_dir()` is the user profile on Windows.
- Engine: `codex-cli/bin/codex.js` runs `vendor/<target triple>/bin/codex.exe` from the optional dependency
  `@openai/codex-win32-x64` / `-arm64`, else from the package's own `vendor` folder — openai/codex `codex-cli/bin/codex.js`.
  npm's global prefix on Windows is `%AppData%\npm`, packages in `{prefix}\node_modules`, shims (`.cmd`) in the prefix —
  npm docs, *Folders* (https://docs.npmjs.com/cli/configuring-npm/folders).

### GitHub Copilot CLI and the GitHub CLI sign-in

- Copilot CLI: `%USERPROFILE%\.copilot`, moved by `COPILOT_HOME` — GitHub Docs, *Copilot CLI configuration directory
  reference* (docs.github.com, `cli-config-dir-reference`).
- `gh` keeps its token through go-keyring: on Windows a generic Credential Manager entry whose target is
  `<service>:<user>` (zalando/go-keyring `keyring_windows.go`, `credName`), service `gh:<host>`, empty user for the
  active account (cli/cli `internal/config/config.go`, `keyringServiceName`, `TokenFromKeyring`) → target
  `gh:github.com:`.
- `hosts.yml`: `GH_CONFIG_DIR`, else `XDG_CONFIG_HOME\gh`, else `%AppData%\GitHub CLI` on Windows (cli/go-gh
  `pkg/config/config.go`, `ConfigDir`).

### Cursor

- User data: `%APPDATA%\Cursor\User\globalStorage\state.vscdb` — Cursor community forum (staff answers on where Cursor
  keeps its state on Windows); Cursor is a VS Code fork, whose user data folder on Windows is `%APPDATA%\<product>`
  (VS Code docs, *Settings → Settings file locations*).

### OpenCode

- Data `%USERPROFILE%\.local\share\opencode` on Windows — OpenCode docs, *Troubleshooting → Storage*
  (opencode.ai/docs/troubleshooting); OpenCode uses the XDG folders on every platform, `XDG_DATA_HOME` and
  `XDG_CONFIG_HOME` first.
- Config `~/.config/opencode/opencode.json` — OpenCode docs, *Config* ("Place your global OpenCode config in
  `~/.config/opencode/opencode.json`", no platform named; opencode.ai/docs/config), the same XDG layout as the data
  folder above.

### Pi, Kimi Code, Qwen Code, CodeBuddy, OpenClaw, Hermes, Grok

- Pi: `~/.pi/agent`, `PI_CODING_AGENT_DIR` — pi.dev docs, *Configuration*.
- Kimi Code: `~/.kimi-code`, `KIMI_CODE_HOME` — Kimi Code docs, *Data locations* (kimi.com).
- Qwen Code: `~/.qwen` (`settings.json`, projects) — qwen-code docs, `settings.md`.
- CodeBuddy Code: `C:\Users\<user>\.codebuddy` — Tencent Cloud CodeBuddy docs.
- OpenClaw: `~/.openclaw`, `OPENCLAW_STATE_DIR` — docs.openclaw.ai, *Where things live on disk*.
- Hermes Agent: `~/.hermes`, `HERMES_HOME`; native Windows is an early beta — Hermes Agent docs, *Installation*.
- Grok CLI: `%USERPROFILE%\.grok`, `GROK_HOME` — docs.x.ai, Grok CLI guides.

`~` is the user profile on Windows for these Node and Python clients (`os.homedir()`, `Path.home()`).

### DeepSeek Harness

- The CLI runs on Windows under Node.js for Windows (`npm install -g @deepseek-ai/dsh`), Node 22.19 or newer, Node 24
  recommended for its built-in Zstandard — Ollama docs, *DeepSeek Harness* (https://docs.ollama.com/integrations/deepseek-harness);
  OrcaRouter, *DeepSeek Harness on Windows* (https://www.orcarouter.ai/blog/deepseek-harness-windows-tui).
- Data `~/.dsh` (settings, profiles, sessions), `DSH_HOME` — same Ollama page.
- The credentials package is looked for in npm's global folder `%AppData%\npm\node_modules` and its npx cache
  `%LocalAppData%\npm-cache\_npx` (npm docs, *Folders*; *config → cache*).
