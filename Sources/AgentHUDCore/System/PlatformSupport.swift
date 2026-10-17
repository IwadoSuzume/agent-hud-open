import Foundation

/// What this platform's build reads. On macOS, everything; on Windows, only the clients whose Windows locations rest
/// on a source (docs/windows-port/SUPPORT_MATRIX.md): a client without one is treated as absent, so it is neither read
/// nor given hooks, and the interface says it is not supported there.
public enum PlatformSupport {
    /// Whether this build supports `source` at all.
    public static func supports(_ source: AdditionalSource) -> Bool {
        #if os(Windows)
        // Antigravity: only community reports place it on Windows; ZCode, WorkBuddy: no Windows location found.
        ![.antigravity, .zcode, .workbuddy].contains(source)
        #else
        true
        #endif
    }

    /// Whether this build reads DeepSeek Harness's desktop app (the CLI is read on every platform).
    public static var supportsDeepSeekDesktop: Bool {
        #if os(Windows)
        false
        #else
        true
        #endif
    }
}
