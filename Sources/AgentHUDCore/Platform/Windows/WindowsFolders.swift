#if os(Windows)
import Foundation
import WinSDK

/// The per-user folders the Windows build keeps its files in and reads clients' files from.
///
/// Foundation's `FileManager.urls(for:in:)` maps Application Support to `%LOCALAPPDATA%` and Caches to `%TEMP%` on
/// Windows, and traps when the folder it computes is missing; `homeDirectoryForCurrentUser` ignores `USERPROFILE`. So
/// the port names its folders itself: the environment variable Windows sets for each, which tests point at a
/// temporary folder, when it holds an absolute path to an existing folder, else the shell's known folder
/// (docs/windows-port/DECISIONS.md D-008, D-020).
public enum WindowsFolders {
    /// `%USERPROFILE%`, the user's home: where clients keep `.claude`, `.codex` and the like.
    public static var profile: URL {
        if let value = Win32.environment("USERPROFILE"), let url = existingFolder(value) { return url }
        if let url = Win32.knownFolder(FOLDERID_Profile) { return url }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `%APPDATA%`, the roaming application data folder: where the data directory lives
    /// (`%APPDATA%\Agent HUD Open`), as `~/Library/Application Support` holds it on macOS.
    public static var roamingAppData: URL {
        folder(environment: "APPDATA", known: FOLDERID_RoamingAppData, fallback: "AppData/Roaming")
    }

    /// `%LOCALAPPDATA%`, the local application data folder: where the instance lock lives
    /// (`%LOCALAPPDATA%\app.agenthud\instance.lock`), as `~/Library/Caches` holds it on macOS.
    public static var localAppData: URL {
        folder(environment: "LOCALAPPDATA", known: FOLDERID_LocalAppData, fallback: "AppData/Local")
    }

    private static func folder(environment name: String, known: KNOWNFOLDERID, fallback: String) -> URL {
        if let value = Win32.environment(name), let url = existingFolder(value) { return url }
        if let url = Win32.knownFolder(known) { return url }
        return profile.appendingPathComponent(fallback, isDirectory: true)
    }

    /// `value` as a folder when it is an absolute drive or UNC path to a folder that exists; a relative or empty value
    /// would resolve against the working directory.
    static func existingFolder(_ value: String) -> URL? {
        guard isAbsolute(value) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// A drive path (`C:\…`, `C:/…`) or a UNC path (`\\server\share\…`).
    static func isAbsolute(_ path: String) -> Bool {
        let scalars = Array(path.unicodeScalars)
        if scalars.count >= 3, ("A"..."Z").contains(scalars[0]) || ("a"..."z").contains(scalars[0]),
           scalars[1] == ":", scalars[2] == "\\" || scalars[2] == "/" {
            return true
        }
        return path.hasPrefix(#"\\"#) || path.hasPrefix("//")
    }
}
#endif
