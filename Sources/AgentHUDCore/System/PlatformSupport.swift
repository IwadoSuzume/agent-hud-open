import Foundation

/// What this platform's build reads. On macOS, everything; on Windows, only the clients whose Windows locations rest
/// on a source (docs/windows-port/SUPPORT_MATRIX.md): a client without one is treated as absent, so it is neither read
/// nor given hooks, and the interface says it is not supported there.
package enum PlatformSupport {
    /// Whether this build supports `source` at all.
    package static func supports(_ source: AdditionalSource) -> Bool {
        #if os(Windows)
        // Antigravity: only community reports place it on Windows; ZCode, WorkBuddy: no Windows location found.
        ![.antigravity, .zcode, .workbuddy].contains(source)
        #else
        true
        #endif
    }

    /// Whether this build reads the desktop apps whose data only macOS places name: Claude's desktop app (its engine and
    /// its Code sessions), the Codex app, Grok Bot and DeepSeek Harness's app. The clients' command-line tools are read on
    /// every platform. On Windows no source gives these apps' folders, so none of their macOS folders is looked for.
    package static var supportsDesktopApps: Bool {
        #if os(Windows)
        false
        #else
        true
        #endif
    }
}
