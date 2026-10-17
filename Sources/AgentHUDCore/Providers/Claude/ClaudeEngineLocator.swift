import Foundation

/// Finds the Claude Code engine binary. GUI apps get a minimal PATH, so the CLI's install places are checked directly; the
/// native installer keeps its versions under `~/.local/share/claude/versions`. `PATH` follows, as for every client's
/// executable (`Executables`). The desktop app does not use any of these: it downloads its own engine for the Code tab to
/// `~/Library/Application Support/Claude/claude-code/<version>/<build>/claude.app`, which comes last, so a Mac with only
/// the desktop app still has an engine and a CLI install is preferred wherever there is one.
public enum ClaudeEngineLocator {
    public static func candidates(home: URL = UserHome.directory,
                                  path: String = Executables.systemPath) -> [URL] {
        cli(home: home, path: path) + (PlatformSupport.supportsDesktopApps ? desktop(home: home) : [])
    }

    /// The CLI's install places and `PATH`, without the desktop app's engines.
    static func cli(home: URL, path: String) -> [URL] {
        #if os(Windows)
        // The native installer's place (docs/windows-port/SUPPORT_MATRIX.md); the others are macOS's.
        let list = [home.appendingPathComponent(".local/bin/claude")]
        #else
        let list = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        #endif
        let versions = home.appendingPathComponent(".local/share/claude/versions", isDirectory: true)
        return list + newestFirst(in: versions) + Executables.onPath("claude", path: path)
    }

    public static func find(home: URL = UserHome.directory, fileManager: FileManager = .default,
                            path: String = Executables.systemPath) -> URL? {
        Executables.first(candidates(home: home, path: path), fileManager: fileManager)
    }

    /// The desktop app's engines, newest version first.
    static func desktop(home: URL) -> [URL] {
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
        return newestFirst(in: root).flatMap { version in
            newestFirst(in: version).map { $0.appendingPathComponent("claude.app/Contents/MacOS/claude") }
        }
    }

    /// The visible entries of `directory`, highest version number first.
    private static func newestFirst(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { directory.appendingPathComponent($0) }
    }
}
