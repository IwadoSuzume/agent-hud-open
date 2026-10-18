#if os(Windows)
import Foundation
import WinSDK

/// The lock that lets only one Agent HUD run at a time, on Windows.
///
/// As on macOS, the copy that runs points every client hook at itself and serves the pipes those hooks reach, so a
/// second copy would take them from under the first. The lock is the file `%LOCALAPPDATA%\app.agenthud\instance.lock`
/// held open for writing without letting anyone else write it (`FILE_SHARE_READ` only), which the system lets go of when
/// the process ends, also when it crashes. The handle is not inheritable, so a client's engine the app starts never
/// holds it after the app is gone. The holder writes its executable's path and its process id, one to a line, so that
/// a launch it turns away can say which copy runs and a reader can tell, without taking the lock, whether that copy
/// still runs.
public final class InstanceLock: @unchecked Sendable {
    public enum Claim: Sendable {
        /// This process holds the lock for as long as it keeps the value.
        case acquired(InstanceLock)
        /// Another process holds it: the application it runs, if the lock names it.
        case held(by: URL?)
        /// No lock could be taken here; the application runs without one rather than not at all.
        case unavailable
    }

    /// `%LOCALAPPDATA%\app.agenthud\instance.lock`: outside every application's own data directory, so they all meet
    /// there.
    public static var sharedURL: URL {
        WindowsFolders.localAppData.appendingPathComponent("app.agenthud", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    private let handle: HANDLE

    private init(handle: HANDLE) { self.handle = handle }

    deinit { CloseHandle(handle) }

    /// Takes the lock at `url` and writes `executable` into it, so that a launch it turns away can say which copy runs.
    public static func claim(at url: URL = sharedURL, executable: URL? = Bundle.main.executableURL) -> Claim {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            NSLog("[AgentHUD] No instance lock at %@: %@", url.path, error.localizedDescription)
            return .unavailable
        }
        let handle = Win32.withWide(native(url)) {
            CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_ALWAYS),
                        DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != Win32.invalidHandle else {
            let failure = GetLastError()
            if failure == DWORD(ERROR_SHARING_VIOLATION) || failure == DWORD(ERROR_LOCK_VIOLATION) {
                return .held(by: holder(at: url))
            }
            NSLog("[AgentHUD] No instance lock at %@: Windows error %u", url.path, failure)
            return .unavailable
        }
        let content = Array(((executable?.path ?? "") + "\n" + String(GetCurrentProcessId())).utf8)
        var written: DWORD = 0
        let named = SetFilePointerEx(handle, LARGE_INTEGER(), nil, DWORD(FILE_BEGIN)) && SetEndOfFile(handle)
            && content.withUnsafeBytes { WriteFile(handle, $0.baseAddress, DWORD($0.count), &written, nil) }
            && Int(written) == content.count
        if !named { NSLog("[AgentHUD] Could not name this copy in the instance lock: Windows error %u", GetLastError()) }
        FlushFileBuffers(handle)
        return .acquired(InstanceLock(handle: handle))
    }

    /// The application that holds the lock at `url` now; nil when no copy holds it or the holder has not written its
    /// name yet. It only asks: the file is opened sharing reading and writing, so the lock is never taken, not even for
    /// a moment, and a copy that starts meanwhile is not turned away. A process that must not start the application,
    /// such as `--mcp`, learns from it whether one runs. The system names a process's executable with junctions and
    /// links followed, so a holder that wrote its name through one is compared by the file both names reach.
    static func runningApplication(at url: URL = sharedURL) -> URL? {
        guard let record = record(at: url), let pid = record.pid, let path = record.path,
              let running = WindowsProcesses.imagePath(pid) else { return nil }
        let written = path.replacingOccurrences(of: "\\", with: "/")
        guard running.lowercased() == written.lowercased() || sameFile(running, written) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func sameFile(_ first: String, _ second: String) -> Bool {
        guard let first = WindowsPaths.finalPath(first), let second = WindowsPaths.finalPath(second) else { return false }
        return first.lowercased() == second.lowercased()
    }

    /// The application whose executable the holder wrote. Nil while the holder has not written it yet.
    static func holder(at url: URL) -> URL? {
        record(at: url)?.path.map { URL(fileURLWithPath: $0) }
    }

    /// What the holder wrote: its executable's path and its process id.
    static func record(at url: URL) -> (path: String?, pid: DWORD?)? {
        let handle = Win32.withWide(native(url)) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return nil }
        defer { CloseHandle(handle) }
        var buffer = [UInt8](repeating: 0, count: 4097)
        var count: DWORD = 0
        guard ReadFile(handle, &buffer, DWORD(buffer.count), &count, nil), count > 0, count <= 4096 else { return nil }
        let lines = String(decoding: buffer[..<Int(count)], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        let path = lines.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { WindowsFolders.isAbsolute($0) ? $0 : nil }
        let pid = lines.count > 1 ? DWORD(lines[1].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        return (path, pid)
    }

    private static func native(_ url: URL) -> String { url.path.replacingOccurrences(of: "/", with: "\\") }
}
#endif
