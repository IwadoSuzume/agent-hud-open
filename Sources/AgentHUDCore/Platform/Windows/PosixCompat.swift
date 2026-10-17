#if os(Windows)
import Foundation
import WinSDK

// The few POSIX names the shared code uses as plain values or pure functions, given the meaning they have on macOS.
// Anything that asks the system about users, processes or sockets is not here: each such call has its own Windows
// implementation, or none where the feature is not supported on Windows (docs/windows-port/PORTING_PLAN.md).

/// A process identifier, as `pid_t` is on macOS; Windows process ids are 32-bit too.
typealias pid_t = Int32
/// A user identifier field kept in shared types; Windows identifies users by SID, and no Windows code path compares one.
typealias uid_t = UInt32

/// `memmem(3)`: the first occurrence of `needle` in `haystack`, or nil.
func memmem(_ haystack: UnsafeRawPointer?, _ haystackLength: Int, _ needle: UnsafeRawPointer?, _ needleLength: Int)
    -> UnsafeMutableRawPointer? {
    guard let haystack, haystackLength >= needleLength else { return nil }
    guard let needle, needleLength > 0 else { return UnsafeMutableRawPointer(mutating: haystack) }
    let first = needle.load(as: UInt8.self)
    var cursor = haystack
    var remaining = haystackLength
    while remaining >= needleLength {
        guard let hit = memchr(cursor, Int32(first), remaining - needleLength + 1) else { return nil }
        if memcmp(hit, needle, needleLength) == 0 { return hit }
        let advance = UnsafeRawPointer(hit) - cursor + 1
        cursor += advance
        remaining -= advance
    }
    return nil
}

/// `realpath(3)`: the final path of an existing file or folder, its links and junctions followed, as Foundation writes
/// paths on Windows (`C:/Users/…`); nil when it does not exist. The result is the caller's to `free`.
func realpath(_ path: String, _ resolved: UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let final = WindowsPaths.finalPath(path) else { return nil }
    return _strdup(final)
}

/// `realpath(3)` for a UTF-8 C string.
func realpath(_ path: UnsafePointer<CChar>, _ resolved: UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    realpath(String(cString: path), resolved)
}

/// Paths as Windows resolves them.
enum WindowsPaths {
    /// Whether `path` is a drive's root (`C:/`, `C:\`), a share's root (`//server/share`), or not an absolute Windows
    /// path at all: where walking up a path must stop.
    static func isRootOrRelative(_ path: String) -> Bool {
        guard WindowsFolders.isAbsolute(path) else { return true }
        let unc = path.hasPrefix("//") || path.hasPrefix(#"\\"#)
        let fixed = unc ? 2 : 1
        var parts: [Substring] = []
        for part in path.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if parts.count > fixed { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return parts.count <= fixed
    }

    /// The final path of an existing file or folder, links and junctions followed, without the `\\?\` prefix and with
    /// forward slashes, as Foundation's `URL.path` writes it; nil when it does not exist.
    static func finalPath(_ path: String) -> String? {
        let native = path.replacingOccurrences(of: "/", with: "\\")
        let handle = Win32.withWide(native) {
            CreateFileW($0, 0, DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return nil }
        defer { CloseHandle(handle) }
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let length = GetFinalPathNameByHandleW(handle, &buffer, DWORD(buffer.count), DWORD(FILE_NAME_NORMALIZED))
        guard length > 0, Int(length) < buffer.count else { return nil }
        var result = String(decoding: buffer[..<Int(length)], as: UTF16.self)
        if result.hasPrefix(#"\\?\UNC\"#) { result = #"\\"# + result.dropFirst(8) }
        else if result.hasPrefix(#"\\?\"#) { result = String(result.dropFirst(4)) }
        return result.replacingOccurrences(of: "\\", with: "/")
    }
}
#endif

#if os(Windows)
/// The longest path `proc_pidpath` writes here: Windows long paths, in UTF-8.
let MAXPATHLEN: Int32 = 32_768 * 3

/// `proc_pidpath(3)`: the full path of the executable the process `pid` runs, written as NUL-terminated UTF-8 into
/// `buffer`; the length written, or 0 when the process cannot be opened, such as another user's.
func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ size: UInt32) -> Int32 {
    guard let buffer, size > 0, let path = WindowsProcesses.imagePath(DWORD(bitPattern: pid)) else { return 0 }
    let bytes = Array(path.utf8)
    guard bytes.count < Int(size) else { return 0 }
    bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
    buffer.storeBytes(of: 0, toByteOffset: bytes.count, as: UInt8.self)
    return Int32(bytes.count)
}
#endif

#if os(Windows)
/// `strcasestr(3)`: the first occurrence of `needle` in `haystack`, ASCII letters matched whatever their case, as the C
/// locale matches them.
func strcasestr(_ haystack: UnsafePointer<CChar>, _ needle: String) -> UnsafePointer<CChar>? {
    let pattern = Array(needle.utf8).map(lowered)
    guard !pattern.isEmpty else { return haystack }
    let length = strlen(haystack)
    guard length >= pattern.count else { return nil }
    let bytes = UnsafeRawPointer(haystack).assumingMemoryBound(to: UInt8.self)
    var start = 0
    while start + pattern.count <= length {
        var index = 0
        while index < pattern.count, lowered(bytes[start + index]) == pattern[index] { index += 1 }
        if index == pattern.count { return haystack + start }
        start += 1
    }
    return nil
}

private func lowered(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }

/// The `os` module's lock, which Windows does not have: the same `withLock` over an `NSLock`.
final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    init(initialState: State) { state = initialState }

    func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
#endif

#if os(Windows)
/// A user id for the shared code that names one, such as the `-U` argument of the process listing, which Windows
/// answers for the current user whatever it says (`ProviderCommand`). It is no user's: Windows has no user ids, and
/// any comparison with a file's owner fails — the C runtime gives every file the owner 0 — so a check that a file is
/// this user's refuses rather than accepts.
func getuid() -> uid_t { uid_t.max }
#endif
