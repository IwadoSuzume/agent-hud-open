import AgentHUDCore
import Foundation

// agenthud-engine.exe, the Windows build's console program (docs/windows-port ADR-001). The clients' hooks and MCP
// servers run it as short-lived processes: a hook hands what the client sent to the running HUD, or waits for the
// user's answer, and quits; `--mcp` serves the client's agent for as long as the client holds its input open. Neither
// starts anything else, and neither opens a window: a console program started by a client that hides its children's
// windows (Codex, Qwen Code) or that runs in a terminal (Claude Code) shows none.
if let status = HookEntry.handle(arguments: CommandLine.arguments) { exit(status) }

// The UI protocol the Windows shell talks to the engine over comes with M6 (PROTOCOL.md). Until then, anything else is
// a mistake to say.
FileHandle.standardError.write(Data("agenthud-engine: no command given (hooks and --mcp only in this build)\n".utf8))
exit(2)
