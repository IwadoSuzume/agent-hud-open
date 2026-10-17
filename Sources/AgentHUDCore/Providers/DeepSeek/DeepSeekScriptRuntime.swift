import Foundation

/// What runs Harness's own JavaScript: Node on this Mac, else the Harness desktop app's Electron in Node mode, as the
/// app's own `dsh` command runs it. The desktop app needs no Node and keeps its packages inside `app.asar`, which only
/// its Electron can load.
struct DeepSeekScriptRuntime: Sendable, Equatable {
    let executable: URL
    /// Added to the helper's environment.
    let environment: [String: String]

    /// The desktop app's name; its bundle identifier is set per build, so the app is looked for by name.
    static let desktopName = "DeepSeek Harness"
    static let applicationFolders = [URL(fileURLWithPath: "/Applications"),
                                     UserHome.directory.appendingPathComponent("Applications")]

    static func node(path: String = Executables.systemPath) -> Self? {
        DeepSeekLocator.nodeExecutable(path: path).map { Self(executable: $0, environment: [:]) }
    }

    static func desktop(_ app: URL) -> Self {
        Self(executable: app.appendingPathComponent("Contents/MacOS/" + desktopName), environment: ["ELECTRON_RUN_AS_NODE": "1"])
    }

    static func desktopApplication(in folders: [URL] = applicationFolders) -> URL? {
        // No source places the desktop app on Windows (docs/windows-port/SUPPORT_MATRIX.md), and `/Applications` would
        // name a folder at the current drive's root that any user may create (D-019): there it is never looked for.
        guard PlatformSupport.supportsDesktopApps else { return nil }
        return folders.map { $0.appendingPathComponent(desktopName + ".app") }
            .first { FileManager.default.isExecutableFile(atPath: desktop($0).executable.path) }
    }

    static func find() -> Self? { node() ?? desktopApplication().map(desktop) }
}
