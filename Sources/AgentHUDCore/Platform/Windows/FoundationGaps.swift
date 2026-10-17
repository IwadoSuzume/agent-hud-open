#if os(Windows)
import Foundation

// Foundation calls the shared code makes that swift-corelibs-foundation does not offer on Windows, with the meaning
// they have on macOS.

extension NSString {
    /// The path with the user's profile folder at its start written `~`, as macOS abbreviates the home directory. A
    /// path elsewhere is returned as it is. Windows compares paths without regard to case.
    var abbreviatingWithTildeInPath: String {
        let path = self as String
        let home = UserHome.directory.standardizedFileURL.path
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !home.isEmpty, normalized.lowercased().hasPrefix(home.lowercased()) else { return path }
        let rest = normalized.dropFirst(home.count)
        guard rest.isEmpty || rest.hasPrefix("/") else { return path }
        return "~" + rest
    }
}
#endif
