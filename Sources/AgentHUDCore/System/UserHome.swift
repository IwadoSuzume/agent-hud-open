import Foundation

/// The user's home folder, where clients keep their dot folders. Core reads it here and nowhere else, so that the
/// Windows build can honour `%USERPROFILE%`, which Foundation ignores there and which tests point at a temporary
/// folder (docs/windows-port/DECISIONS.md D-020). On macOS it is the folder Foundation names.
public enum UserHome {
    public static var directory: URL {
        #if os(Windows)
        WindowsFolders.profile
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }
}
