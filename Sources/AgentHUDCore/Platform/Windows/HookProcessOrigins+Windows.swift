#if os(Windows)
import Foundation
import WinSDK

extension HookProcessOrigins {
    /// The hook's ancestors, from its parent outwards, as the system's process table records them: each one's
    /// executable and the arguments of its command line. Only this user's processes are followed; the walk stops at the
    /// first one that cannot be opened. Windows apps have no bundle identifiers. Process environments are never read.
    static func ancestors() -> [Ancestor] {
        let entries = Dictionary(WindowsProcesses.snapshot().map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var pid = entries[GetCurrentProcessId()]?.parent ?? 0, seen: Set<DWORD> = [], result: [Ancestor] = []
        while pid > 4, result.count < 16, seen.insert(pid).inserted, let entry = entries[pid] {
            guard WindowsProcesses.isCurrentUser(pid), let executable = WindowsProcesses.imagePath(pid),
                  let command = WindowsProcesses.commandLine(pid) else { break }
            result.append(Ancestor(executable: executable, arguments: WindowsCommandLine.split(command)))
            pid = entry.parent
        }
        return result
    }
}

/// Command lines as the C runtime splits them into arguments.
enum WindowsCommandLine {
    static func split(_ command: String) -> [String] {
        var count: Int32 = 0
        guard let arguments = Win32.withWide(command, { CommandLineToArgvW($0, &count) }) else { return [] }
        defer { LocalFree(arguments) }
        return (0..<Int(count)).compactMap { index in arguments[index].map { Win32.string($0) } }
    }
}
#endif
