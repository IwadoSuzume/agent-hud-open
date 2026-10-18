import AgentHUDCore
import Foundation

// agenthud-engine.exe, the Windows build's console program (docs/windows-port ADR-001). The clients' hooks and MCP
// servers run it as short-lived processes: a hook hands what the client sent to the running HUD, or waits for the
// user's answer, and quits; `--mcp` serves the client's agent for as long as the client holds its input open. Neither
// starts anything else, and neither opens a window: a console program started by a client that hides its children's
// windows (Codex, Qwen Code) or that runs in a terminal (Claude Code) shows none.
if let status = HookEntry.handle(arguments: CommandLine.arguments) { exit(status) }

// The Windows shell's child: the protocol over the inherited standard input and output (PROTOCOL.md).
if EngineServe.isRequested(by: CommandLine.arguments) {
    EngineServe.run(arguments: CommandLine.arguments, executable: Bundle.main.executableURL)
}

EngineServe.complain("no command given (--serve, --mcp or a hook)")
exit(2)
