import Foundation

/// Application-owned caches and local usage history.
public enum AppSupport {
    public static var directory: URL {
        #if os(Windows)
        // `%APPDATA%\Agent HUD Open` (docs/windows.md#storage).
        let base = WindowsFolders.roamingAppData
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? UserHome.directory.appendingPathComponent("Library/Application Support")
        #endif
        return base.appendingPathComponent(directoryName(of: .main), isDirectory: true)
    }

    /// The name of the data directory the application in `bundle` keeps: its `AgentHUDDataDirectory`, else
    /// `Agent HUD Open`, as for an executable outside a bundle.
    static func directoryName(of bundle: Bundle?) -> String {
        bundle?.object(forInfoDictionaryKey: "AgentHUDDataDirectory") as? String ?? "Agent HUD Open"
    }
}
