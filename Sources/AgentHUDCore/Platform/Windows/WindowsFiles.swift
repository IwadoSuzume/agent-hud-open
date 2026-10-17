#if os(Windows)
import Foundation
import WinSDK

/// C runtime file descriptors on Windows, opened the way the macOS build opens them: binary (the runtime's text mode
/// would translate line ends and stop at Ctrl-Z), by the path's UTF-16 form so that any user name works, and not
/// inherited by child processes (`O_CLOEXEC`).
enum WindowsFiles {
    /// A descriptor for reading `path`, or -1 with `errno` set.
    static func openForReading(_ path: String) -> Int32 {
        var descriptor: Int32 = -1
        let failure = Win32.withWide(path.replacingOccurrences(of: "/", with: "\\")) {
            _wsopen_s(&descriptor, $0, _O_RDONLY | _O_BINARY | _O_NOINHERIT, _SH_DENYNO, _S_IREAD)
        }
        if failure != 0 { errno = failure }
        return failure == 0 ? descriptor : -1
    }
}
#endif

#if os(Windows)
extension WindowsFiles {
    /// Volume, file index, size and last write time, which any write to the file or its replacement changes: what
    /// device, inode, size and modification time are on macOS. Nil when the file cannot be opened. The file is opened
    /// sharing reading, writing and deletion, so its writer is never held up.
    static func signature(_ path: String) -> [Int]? {
        let handle = Win32.withWide(path.replacingOccurrences(of: "/", with: "\\")) {
            CreateFileW($0, 0, DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return nil }
        defer { CloseHandle(handle) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &info) else { return nil }
        let index = Int(info.nFileIndexHigh) << 32 | Int(info.nFileIndexLow)
        let size = Int(info.nFileSizeHigh) << 32 | Int(info.nFileSizeLow)
        let written = Int(info.ftLastWriteTime.dwHighDateTime) << 32 | Int(info.ftLastWriteTime.dwLowDateTime)
        return [Int(info.dwVolumeSerialNumber), index, size, written]
    }
}
#endif

#if os(Windows)
extension WindowsFiles {
    /// What the file system records about `path` without opening it — kind, last write time and size — so a file a
    /// client holds exclusively is still described. Nil when there is no such file.
    static func attributes(_ path: String) -> (isRegularFile: Bool, modified: Date, size: Int)? {
        var data = WIN32_FILE_ATTRIBUTE_DATA()
        let found = Win32.withWide(path.replacingOccurrences(of: "/", with: "\\")) {
            GetFileAttributesExW($0, GetFileExInfoStandard, &data)
        }
        guard found else { return nil }
        let directory = data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0
        let device = data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DEVICE) != 0
        let ticks = UInt64(data.ftLastWriteTime.dwHighDateTime) << 32 | UInt64(data.ftLastWriteTime.dwLowDateTime)
        // FILETIME counts 100 ns from 1601-01-01; 11,644,473,600 s separate it from 1970.
        let modified = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
        let size = Int(data.nFileSizeHigh) << 32 | Int(data.nFileSizeLow)
        return (!directory && !device, modified, size)
    }
}
#endif

#if os(Windows)
extension WindowsFiles {
    struct Entry {
        let url: URL
        let isDirectory: Bool
        let modified: Date
        let size: Int
    }

    /// The entries under `folder`, depth first, as the file system's directory records name them: files a client holds
    /// exclusively included, which Foundation's enumerator leaves out on Windows. Hidden entries (a leading dot or the
    /// hidden attribute) and reparse points are passed over, as the enumerator's `skipsHiddenFiles` and the listing's
    /// rules do. `visit` returns whether to go into a directory, or nil to stop the walk. Returns the folders that could
    /// not be read.
    @discardableResult
    static func walk(_ folder: URL, visit: (Entry) -> Bool?) -> Int {
        var unreadable = 0
        var pending = [folder]
        while let current = pending.popLast() {
            var data = WIN32_FIND_DATAW()
            let pattern = current.path.replacingOccurrences(of: "/", with: "\\") + #"\*"#
            let handle = Win32.withWide(pattern) {
                FindFirstFileExW($0, FindExInfoBasic, &data, FindExSearchNameMatch, nil, DWORD(FIND_FIRST_EX_LARGE_FETCH))
            }
            guard let handle, handle != Win32.invalidHandle else {
                if GetLastError() != DWORD(ERROR_FILE_NOT_FOUND) { unreadable += 1 }
                continue
            }
            defer { FindClose(handle) }
            var children: [URL] = []
            repeat {
                let name = withUnsafeBytes(of: data.cFileName) { bytes in
                    String(decodingCString: bytes.baseAddress!.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
                }
                if name == "." || name == ".." || name.hasPrefix(".") { continue }
                let attributes = data.dwFileAttributes
                if attributes & DWORD(FILE_ATTRIBUTE_HIDDEN) != 0 { continue }
                let isDirectory = attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0
                let ticks = UInt64(data.ftLastWriteTime.dwHighDateTime) << 32 | UInt64(data.ftLastWriteTime.dwLowDateTime)
                let entry = Entry(url: current.appendingPathComponent(name, isDirectory: isDirectory), isDirectory: isDirectory,
                                  modified: Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600),
                                  size: Int(data.nFileSizeHigh) << 32 | Int(data.nFileSizeLow))
                guard let descend = visit(entry) else { return unreadable }
                if isDirectory, descend, attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 { children.append(entry.url) }
            } while FindNextFileW(handle, &data)
            pending.append(contentsOf: children.reversed())
        }
        return unreadable
    }
}
#endif
