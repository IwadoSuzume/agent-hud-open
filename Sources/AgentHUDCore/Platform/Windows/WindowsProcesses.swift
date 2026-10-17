#if os(Windows)
import Foundation
import WinSDK

/// What the Windows build reads about this user's processes: the stand-in for `ps`, `proc_pidpath` and `lsof` on macOS.
/// Only processes of the current user are described; another user's cannot be opened and are left out. Command lines
/// can hold a client's local token, so what is read stays in memory, as the macOS listing does.
enum WindowsProcesses {
    struct Entry: Equatable, Sendable {
        let pid: DWORD
        let parent: DWORD
        let executableName: String
    }

    /// Every process the system lists, with its parent and executable name.
    static func snapshot() -> [Entry] {
        let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
        guard let snapshot, snapshot != Win32.invalidHandle else { return [] }
        defer { CloseHandle(snapshot) }
        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        var result: [Entry] = []
        var more = Process32FirstW(snapshot, &entry)
        while more {
            let name = withUnsafeBytes(of: entry.szExeFile) { bytes in
                String(decodingCString: bytes.baseAddress!.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
            }
            result.append(Entry(pid: entry.th32ProcessID, parent: entry.th32ParentProcessID, executableName: name))
            more = Process32NextW(snapshot, &entry)
        }
        return result
    }

    /// The full path of the executable `pid` runs, with forward slashes as Foundation writes paths; nil when the
    /// process cannot be opened.
    static func imagePath(_ pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(process) }
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(process, 0, &buffer, &size), size > 0 else { return nil }
        return String(decoding: buffer[..<Int(size)], as: UTF16.self).replacingOccurrences(of: "\\", with: "/")
    }

    /// The command line `pid` was started with, as the system keeps it; nil when the process cannot be opened.
    static func commandLine(_ pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(process) }
        // ProcessCommandLineInformation (60), Windows 8.1 and later: a UNICODE_STRING followed by its characters.
        var size: ULONG = 0
        _ = NtQueryInformationProcess(process, PROCESSINFOCLASS(rawValue: 60), nil, 0, &size)
        guard size > 0, size <= 1024 * 1024 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard NtQueryInformationProcess(process, PROCESSINFOCLASS(rawValue: 60), buffer, size, &size) >= 0 else { return nil }
        let string = buffer.load(as: UNICODE_STRING.self)
        guard let characters = string.Buffer else { return nil }
        return String(decoding: UnsafeBufferPointer(start: characters, count: Int(string.Length) / 2), as: UTF16.self)
    }

    /// Whether `pid` runs as the current user.
    static func isCurrentUser(_ pid: DWORD) -> Bool {
        guard let sid = Win32.currentUserSID else { return false }
        return Win32.userSID(ofProcess: pid) == sid
    }

    /// This user's processes, one to a line, `pid command`, as `ps -U <user> -o pid=,command=` lists them on macOS. A
    /// command's backslashes are written as forward slashes, the separator the shared readers match paths by.
    static func listing() -> String {
        var lines: [String] = []
        for entry in snapshot() where entry.pid != 0 && isCurrentUser(entry.pid) {
            guard let command = commandLine(entry.pid), !command.isEmpty else { continue }
            let flattened = command.replacingOccurrences(of: "\\", with: "/")
                .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            lines.append("\(entry.pid) \(flattened)")
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// The TCP ports `pid` listens on, IPv4 and IPv6, with the address each is bound to.
    static func listeningPorts(_ pid: DWORD) -> [(address: String, port: UInt16)] {
        var result: [(address: String, port: UInt16)] = []
        for family in [AF_INET, AF_INET6] {
            var size: DWORD = 0
            _ = GetExtendedTcpTable(nil, &size, false, ULONG(family), TCP_TABLE_OWNER_PID_LISTENER, 0)
            guard size > 0 else { continue }
            size += 4096
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
            defer { buffer.deallocate() }
            guard GetExtendedTcpTable(buffer, &size, false, ULONG(family), TCP_TABLE_OWNER_PID_LISTENER, 0) == NO_ERROR else {
                continue
            }
            let count = Int(buffer.load(as: DWORD.self))
            if family == AF_INET {
                let rows = buffer.advanced(by: MemoryLayout<DWORD>.stride).assumingMemoryBound(to: MIB_TCPROW_OWNER_PID.self)
                for index in 0..<count where rows[index].dwOwningPid == pid {
                    let row = rows[index]
                    let address = withUnsafeBytes(of: row.dwLocalAddr) { $0.map { String($0) }.joined(separator: ".") }
                    result.append((address, UInt16(bigEndian: UInt16(truncatingIfNeeded: row.dwLocalPort))))
                }
            } else {
                let rows = buffer.advanced(by: MemoryLayout<DWORD>.stride).assumingMemoryBound(to: MIB_TCP6ROW_OWNER_PID.self)
                for index in 0..<count where rows[index].dwOwningPid == pid {
                    let row = rows[index]
                    let bytes = withUnsafeBytes(of: row.ucLocalAddr) { Array($0) }
                    let address = bytes.allSatisfy { $0 == 0 } ? "[::]" : bytes == Array(repeating: 0, count: 15) + [1] ? "[::1]" : "[ipv6]"
                    result.append((address, UInt16(bigEndian: UInt16(truncatingIfNeeded: row.dwLocalPort))))
                }
            }
        }
        return result
    }

    /// The start times of the DeepSeek Harness processes holding a profile of the Harness home `directory`.
    /// Not read on Windows yet (docs/windows-port/SUPPORT_MATRIX.md): no Harness process is reported.
    static func harnessStarts(directory: URL) async -> [Date] { [] }
}

// MARK: - The fixed inspection tools

/// Runs only fixed system inspection tools, as on macOS; on Windows the two the shared readers ask for are answered from
/// the system itself, in the form those tools print, so the readers and their tests stay as they are. Output (including
/// CSRF tokens) stays in memory and is never logged.
enum ProviderCommand {
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        switch executable {
        case "/bin/ps":
            // `ps -U <user> -o pid=,command=`: this user's processes, whatever user the arguments name.
            guard arguments.contains("pid=,command=") else { throw ProviderFailure.format }
            return await Task.detached(priority: .utility) { WindowsProcesses.listing() }.value
        case "/usr/sbin/lsof":
            // `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN -Fn`: the TCP ports one process listens on, as `n<address>:<port>`.
            guard arguments.contains("-sTCP:LISTEN"), let index = arguments.firstIndex(of: "-p"), index + 1 < arguments.count,
                  let pid = DWORD(arguments[index + 1]) else { throw ProviderFailure.format }
            guard WindowsProcesses.isCurrentUser(pid) else { return "" }
            return "p\(pid)\n" + WindowsProcesses.listeningPorts(pid).map { "n\($0.address):\($0.port)\n" }.joined()
        default:
            // No other tool is run on Windows: a POSIX path would resolve against a drive's root (DECISIONS.md D-012).
            throw ProviderFailure.local
        }
    }
}
#endif
