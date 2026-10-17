#if os(Windows)
import Foundation

/// Which programs the Windows build may start (docs/windows-port/DECISIONS.md D-019).
///
/// A candidate is used only when it is an absolute drive or UNC path to an existing Windows program — a PE image, not
/// a batch file. A POSIX path such as `/opt/homebrew/bin/node`, which the macOS locators also list, would resolve
/// against the current drive's root, where any user of the machine may create folders, so it is never a candidate here.
enum WindowsExecutables {
    /// `name` in each absolute directory of a `;`-separated `PATH`, as `name.exe` (batch files are never run, so `.cmd`
    /// and `.bat` are not looked for). Empty and relative entries are passed over.
    static func onPath(_ name: String, path: String) -> [URL] {
        let file = name.lowercased().hasSuffix(".exe") ? name : name + ".exe"
        return path.split(separator: ";").compactMap { entry -> URL? in
            let folder = entry.trimmingCharacters(in: CharacterSet(charactersIn: " \"")).replacingOccurrences(of: "\\", with: "/")
            guard WindowsFolders.isAbsolute(folder) else { return nil }
            return URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(file)
        }
    }

    /// `candidate` as a program that may be started, trying `.exe` when it names none; nil otherwise.
    static func program(_ candidate: URL) -> URL? {
        let path = candidate.path
        guard WindowsFolders.isAbsolute(path) else { return nil }
        let names = candidate.pathExtension.isEmpty ? [candidate.appendingPathExtension("exe"), candidate] : [candidate]
        return names.first { url in
            guard let facts = WindowsFiles.attributes(url.path), facts.isRegularFile,
                  !ChildProcess.isBatchFile(url.lastPathComponent) else { return false }
            return ChildProcess.isProgramImage(url.path.replacingOccurrences(of: "/", with: "\\"))
        }
    }
}
#endif
