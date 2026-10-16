# Windows support matrix

What the Windows build does for each client, and the source each Windows-specific fact rests on (TASK.md §3, §7.2).
A fact without a source is not used: the client, or that part of it, is **not supported on Windows** and Settings says
so. Status values: ✅ supported and tested with fixtures, 🔶 not supported on Windows (reason given), ⏳ planned in a
later milestone.

Columns: **Sessions/usage** (local records → sessions, tokens, ledger), **Quota** (account quota or balance
request), **Approvals** (permission hook or native requests), **Completion** (stop/completion hook or observer),
**Jump** (reveal the session's terminal or window).

| Client | Sessions/usage | Quota | Approvals | Completion | Jump |
| --- | --- | --- | --- | --- | --- |
| Claude Code | ⏳ | ⏳ | ⏳ | ⏳ | 🔶 |
| (all others) | ⏳ | ⏳ | ⏳ | ⏳ | 🔶 |

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

### GitHub Copilot CLI (GitHub CLI sign-in)

- `gh` keeps its token through go-keyring: on Windows a generic Credential Manager entry whose target is
  `<service>:<user>` (zalando/go-keyring `keyring_windows.go`, `credName`), service `gh:<host>`, empty user for the
  active account (cli/cli `internal/config/config.go`, `keyringServiceName`, `TokenFromKeyring`) → target
  `gh:github.com:`.
- `hosts.yml`: `GH_CONFIG_DIR`, else `XDG_CONFIG_HOME\gh`, else `%AppData%\GitHub CLI` on Windows (cli/go-gh
  `pkg/config/config.go`, `ConfigDir`).
