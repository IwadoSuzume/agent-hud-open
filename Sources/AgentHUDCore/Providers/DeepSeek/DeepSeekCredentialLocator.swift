import Foundation

enum DeepSeekCredentialLocator {
    /// Harness's credentials package and a runtime that can load it.
    struct Harness: Sendable, Equatable {
        let module: URL?
        let runtime: DeepSeekScriptRuntime?
    }

    static let package = "@deepseek-ai/dsh-credentials-local/lib/index.js"

    /// A CLI install's package, run by Node or else by the desktop app; otherwise the desktop app's own, which sits in
    /// its `app.asar` with every other package its runtime ships, side by side, and loads only in its Electron.
    static func locate(home: URL = UserHome.directory,
                       path: String = Executables.systemPath,
                       applications: [URL] = DeepSeekScriptRuntime.applicationFolders) -> Harness {
        let desktop = DeepSeekScriptRuntime.desktopApplication(in: applications)
        if let module = module(home: home) {
            return Harness(module: module, runtime: DeepSeekScriptRuntime.node(path: path) ?? desktop.map(DeepSeekScriptRuntime.desktop))
        }
        if let desktop {
            return Harness(module: desktop.appendingPathComponent("Contents/Resources/app.asar/dsh/node_modules").appendingPathComponent(package),
                           runtime: .desktop(desktop))
        }
        return Harness(module: nil, runtime: DeepSeekScriptRuntime.node(path: path))
    }

    static func module(home: URL = UserHome.directory) -> URL? {
        #if os(Windows)
        // npm's global packages and its npx cache on Windows (npm docs, *Folders* and *config: cache*), the install the
        // DeepSeek Harness docs give; a POSIX folder would name the current drive's root, where any user may plant the
        // module Node then loads (D-019), and Bun's global folder has no documented place on Windows.
        var roots = [WindowsFolders.roamingAppData.appendingPathComponent("npm/node_modules")]
        let cache = WindowsFolders.localAppData.appendingPathComponent("npm-cache/_npx")
        #else
        var roots = ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules"].map { URL(fileURLWithPath: $0) }
        roots.append(home.appendingPathComponent(".bun/install/global/node_modules"))
        let cache = home.appendingPathComponent(".npm/_npx")
        #endif
        if let installs = try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.contentModificationDateKey]) {
            roots += installs.sorted { a, b in
                ((try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }.map { $0.appendingPathComponent("node_modules") }
        }
        return roots.map { $0.appendingPathComponent(package) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
