#if os(Windows)
import Foundation
import WinSDK

/// The Windows stand-in for the `os.Logger` lines the macOS build writes: each line goes to the debugger output
/// (`OutputDebugStringW`, read with DebugView or a debugger) and, when `AGENTHUD_LOG` is set to `stderr`, to standard
/// error. Callers pass only what the macOS build marks `.public`: paths, states and error codes, never a credential,
/// a request's content or conversation text.
enum PlatformLog {
    static func info(_ category: String, _ message: String) { write("info", category, message) }
    static func error(_ category: String, _ message: String) { write("error", category, message) }

    private static let toStandardError = ProcessInfo.processInfo.environment["AGENTHUD_LOG"] == "stderr"

    private static func write(_ level: String, _ category: String, _ message: String) {
        let line = "[AgentHUD] [\(category)] \(level): \(message)\n"
        Win32.withWide(line) { OutputDebugStringW($0) }
        if toStandardError { FileHandle.standardError.write(Data(line.utf8)) }
    }
}
#endif
