import Foundation

/// Paths as the file system compares them: as written on macOS, without regard to case on Windows, whose file systems
/// ignore it (docs/windows-port/DECISIONS.md D-023). Used wherever Core matches one path against another.
enum PathCase {
    static func folded(_ path: String) -> String {
        #if os(Windows)
        path.lowercased()
        #else
        path
        #endif
    }
}
