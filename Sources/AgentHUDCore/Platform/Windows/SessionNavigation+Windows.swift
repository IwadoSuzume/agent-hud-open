#if os(Windows)
import Foundation

// Revealing the terminal a session runs in: on macOS the app matches a client's process to its iTerm2 or Terminal
// window through the kernel's process table and each process's environment. The Windows build does not offer it yet
// (docs/windows-port/SUPPORT_MATRIX.md, "Session jump"), so no session carries a destination and the HUD shows no
// button for one. The pure parsing these features use stays shared and tested.

extension CodexTerminalOrigins {
    static func listenerTargets(ports: Set<UInt16>) -> [UInt16: SessionNavigationTarget] { [:] }
}
#endif
