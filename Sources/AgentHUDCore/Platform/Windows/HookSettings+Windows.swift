#if os(Windows)
import Foundation
import WinSDK

extension HookSettings {
    /// One `ReplaceFileW(target, staged, backup)` call: nil when it succeeded, else the error it ended with. A
    /// parameter so that tests can make each of its failures happen (HookFormsWindowsTests).
    typealias Replace = @Sendable (_ target: String, _ staged: String, _ backup: String) -> DWORD?

    static let systemReplace: Replace = { target, staged, backup in
        let replaced = Win32.withWide(target) { target in
            Win32.withWide(staged) { staged in
                Win32.withWide(backup) { backup in
                    ReplaceFileW(target, staged, backup, DWORD(REPLACEFILE_IGNORE_MERGE_ERRORS), nil, nil)
                }
            }
        }
        return replaced ? nil : GetLastError()
    }

    /// Writes `data` as the whole of `file` so that a settings file already there keeps its security descriptor, its
    /// attributes and its creation time (docs/windows-port/DECISIONS.md D-023): the content goes to a new file beside it,
    /// which `ReplaceFileW` puts in its place, keeping the old one under a backup name until the new one is there.
    /// Foundation's atomic write would move a new file there instead, which takes the folder's inherited permissions
    /// and drops any the user gave the file. A file that is not there yet is moved into place and takes the folder's,
    /// as on macOS.
    ///
    /// When a step fails the user's file is never lost: `ReplaceFileW` can fail after it moved the old file to the
    /// backup name (`ERROR_UNABLE_TO_MOVE_REPLACEMENT_2`), and then the backup is moved back. The staged file is removed
    /// only once the user's file is in place again, and the backup only once the new file is.
    static func replaceKeepingSecurity(_ data: Data, at file: URL, replace: Replace = systemReplace) throws {
        let folder = file.deletingLastPathComponent()
        let token = UUID().uuidString
        let staged = folder.appendingPathComponent(".\(file.lastPathComponent).agenthud-\(token).tmp")
        let backup = folder.appendingPathComponent(".\(file.lastPathComponent).agenthud-\(token).backup")
        try data.write(to: staged, options: .withoutOverwriting)
        let target = native(file), source = native(staged), saved = native(backup)
        guard FileManager.default.fileExists(atPath: file.path) else {
            let moved = Win32.withWide(source) { source in
                Win32.withWide(target) { target in MoveFileExW(source, target, DWORD(MOVEFILE_WRITE_THROUGH)) }
            }
            guard moved else {
                let code = GetLastError()
                try? FileManager.default.removeItem(at: staged)
                throw failure(file, code)
            }
            return
        }
        guard let code = replace(target, source, saved) else {
            // The new file is in place; the old one, kept until now, can go.
            try? FileManager.default.removeItem(at: backup)
            return
        }
        // The old file was moved aside and the new one could not take its place: put the old one back.
        if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: backup.path) {
            _ = Win32.withWide(saved) { saved in
                Win32.withWide(target) { target in MoveFileExW(saved, target, DWORD(MOVEFILE_WRITE_THROUGH)) }
            }
        }
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: staged)
            if FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.removeItem(at: backup) }
        }
        // Otherwise nothing more is touched: whatever copy is left beside it is the user's, named in the log.
        else {
            PlatformLog.error("hooks", "Settings file \(file.path) could not be put back; its content is in \(backup.path) or \(staged.path)")
        }
        throw failure(file, code)
    }

    private static func failure(_ file: URL, _ code: DWORD) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path,
                                                 NSUnderlyingErrorKey: NSError(domain: "Win32", code: Int(code))])
    }

    /// The path as Windows file calls take it, in its `\\?\` form when it is longer than `MAX_PATH` allows.
    static func native(_ url: URL) -> String {
        let path = url.path.replacingOccurrences(of: "/", with: "\\")
        guard path.count >= Int(MAX_PATH) - 12 else { return path }
        if path.hasPrefix(#"\\?\"#) { return path }
        if path.hasPrefix(#"\\"#) { return #"\\?\UNC\"# + path.dropFirst(2) }
        return #"\\?\"# + path
    }
}
#endif
