#if os(Windows)
import Foundation
import WinSDK

extension HookSettings {
    /// Writes `data` as the whole of `file` so that a settings file already there keeps its security descriptor, its
    /// attributes and its creation time (docs/windows-port/DECISIONS.md D-023): the content goes to a new file beside it,
    /// which `ReplaceFileW` puts in its place. Foundation's atomic write would move a new file there instead, which takes
    /// the folder's inherited permissions and drops any the user gave the file. A file that is not there yet is moved
    /// into place and takes the folder's, as on macOS. Nothing is left behind when a step fails.
    static func replaceKeepingSecurity(_ data: Data, at file: URL) throws {
        let folder = file.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".\(file.lastPathComponent).agenthud-\(UUID().uuidString).tmp")
        try data.write(to: staged, options: .withoutOverwriting)
        let target = file.path.replacingOccurrences(of: "/", with: "\\")
        let source = staged.path.replacingOccurrences(of: "/", with: "\\")
        let replaced: Bool
        if FileManager.default.fileExists(atPath: file.path) {
            replaced = Win32.withWide(target) { target in
                Win32.withWide(source) { source in
                    ReplaceFileW(target, source, nil, DWORD(REPLACEFILE_IGNORE_MERGE_ERRORS), nil, nil)
                }
            }
        } else {
            replaced = Win32.withWide(source) { source in
                Win32.withWide(target) { target in MoveFileExW(source, target, DWORD(MOVEFILE_WRITE_THROUGH)) }
            }
        }
        guard replaced else {
            let code = GetLastError()
            try? FileManager.default.removeItem(at: staged)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path,
                                                          NSUnderlyingErrorKey: NSError(domain: "Win32", code: Int(code))])
        }
    }
}
#endif
