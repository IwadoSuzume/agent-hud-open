import Foundation

/// Grok Bot is a desktop client with a data directory separate from Grok CLI and Cursor.
public enum GrokBotLocator {
    public static func isInstalled(home: URL = UserHome.directory,
                                   applicationURLs: [URL]? = nil) -> Bool {
        let data = home.appendingPathComponent("Library/Application Support/Grok Bot", isDirectory: true)
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: data.path, isDirectory: &directory), directory.boolValue { return true }
        #if os(Windows)
        // `/Applications` would name a folder at the current drive's root that any user may create (D-019).
        let system: [URL] = []
        #else
        let system = [URL(fileURLWithPath: "/Applications/Grok Bot.app", isDirectory: true)]
        #endif
        let apps = applicationURLs ?? VendorCatalog.applications("Grok Bot") + system + [
            home.appendingPathComponent("Applications/Grok Bot.app", isDirectory: true),
        ]
        return apps.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}
