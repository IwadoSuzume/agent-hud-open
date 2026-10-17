#if os(Windows)
import Foundation

/// Where npm puts the Codex CLI's native engine on Windows, so that it can run without `codex.cmd`, npm's batch shim,
/// which the Windows build never starts (DECISIONS.md D-011).
///
/// - npm's global prefix on Windows is `%AppData%\npm`, global packages live in `{prefix}\node_modules` and their own
///   dependencies in the package's `node_modules` (npm docs, *Folders*);
/// - the `@openai/codex` package runs `vendor/<target triple>/bin/codex.exe` from the optional package
///   `@openai/codex-win32-x64` (or `-arm64`), else from its own `vendor` folder (openai/codex, `codex-cli/bin/codex.js`).
enum WindowsCodex {
    static func engines(appData: URL = WindowsFolders.roamingAppData) -> [URL] {
        let package = appData.appendingPathComponent("npm/node_modules/@openai/codex")
        let targets = [("x86_64-pc-windows-msvc", "codex-win32-x64"), ("aarch64-pc-windows-msvc", "codex-win32-arm64")]
        return targets.flatMap { triple, platformPackage in
            [package.appendingPathComponent("node_modules/@openai/\(platformPackage)/vendor/\(triple)/bin/codex.exe"),
             appData.appendingPathComponent("npm/node_modules/@openai/\(platformPackage)/vendor/\(triple)/bin/codex.exe"),
             package.appendingPathComponent("vendor/\(triple)/bin/codex.exe")]
        }
    }
}
#endif
