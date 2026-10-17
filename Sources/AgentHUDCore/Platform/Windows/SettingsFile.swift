#if os(Windows)
import Foundation

/// The preferences of the Windows build: the `UserDefaults` the settings and layout stores are given, kept in a JSON
/// file instead of a CoreFoundation domain (docs/windows-port/DECISIONS.md D-018). swift-corelibs `UserDefaults` would
/// write `<suite>.plist` straight into `%LOCALAPPDATA%`; this keeps `%APPDATA%\Agent HUD Open\settings.json`, written
/// whole and atomically after every change.
///
/// Only what the stores keep is supported: data and booleans. Every way of setting or reading a value is overridden,
/// so that nothing falls through to the CoreFoundation domain beneath; a value of another type is not stored.
public final class SettingsFile: UserDefaults, @unchecked Sendable {
    private enum Stored: Codable, Equatable {
        case data(Data)
        case bool(Bool)
    }

    private struct Document: Codable {
        var version = 1
        var values: [String: Stored] = [:]
    }

    /// The file; nil keeps the values in memory only, for snapshot runs and tests.
    public let url: URL?
    private let lock = NSLock()
    private var values: [String: Stored]

    /// `%APPDATA%\Agent HUD Open\settings.json`, or `settings.demo.json` for the demo.
    public static func standard(demo: Bool = false) -> SettingsFile {
        SettingsFile(url: AppSupport.directory.appendingPathComponent(demo ? "settings.demo.json" : "settings.json"))!
    }

    /// The preferences in `url`; a missing or unreadable file starts empty, and is replaced at the first change.
    public init?(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url), let document = try? JSONDecoder().decode(Document.self, from: data) {
            values = document.values
        } else {
            values = [:]
        }
        // The domain beneath is never written: every accessor below answers from `values`.
        super.init(suiteName: "app.agenthud.settings-file")
    }

    private func read(_ key: String) -> Stored? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    private func write(_ key: String, _ value: Stored?) {
        lock.lock()
        let changed = values[key] != value
        values[key] = value
        let document = Document(values: values)
        lock.unlock()
        guard changed, let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch {
            NSLog("[AgentHUD] Could not save the settings at %@: %@", url.path, error.localizedDescription)
        }
    }

    public override func object(forKey defaultName: String) -> Any? {
        switch read(defaultName) {
        case .data(let data): data
        case .bool(let value): value
        case nil: nil
        }
    }

    public override func data(forKey defaultName: String) -> Data? {
        if case .data(let data) = read(defaultName) { return data }
        return nil
    }

    public override func bool(forKey defaultName: String) -> Bool {
        if case .bool(let value) = read(defaultName) { return value }
        return false
    }

    public override func string(forKey defaultName: String) -> String? { nil }
    public override func integer(forKey defaultName: String) -> Int { 0 }
    public override func double(forKey defaultName: String) -> Double { 0 }
    public override func float(forKey defaultName: String) -> Float { 0 }
    public override func url(forKey defaultName: String) -> URL? { nil }
    public override func array(forKey defaultName: String) -> [Any]? { nil }
    public override func dictionary(forKey defaultName: String) -> [String: Any]? { nil }
    public override func stringArray(forKey defaultName: String) -> [String]? { nil }

    public override func set(_ value: Any?, forKey defaultName: String) {
        switch value {
        case nil: write(defaultName, nil)
        case let data as Data: write(defaultName, .data(data))
        case let flag as Bool: write(defaultName, .bool(flag))
        default: unsupported(defaultName)
        }
    }

    public override func set(_ value: Bool, forKey defaultName: String) { write(defaultName, .bool(value)) }
    public override func set(_ value: Int, forKey defaultName: String) { unsupported(defaultName) }
    public override func set(_ value: Double, forKey defaultName: String) { unsupported(defaultName) }
    public override func set(_ value: Float, forKey defaultName: String) { unsupported(defaultName) }
    public override func set(_ url: URL?, forKey defaultName: String) { unsupported(defaultName) }

    private func unsupported(_ key: String) {
        NSLog("[AgentHUD] A setting of an unsupported type was not saved: %@", key)
    }

    public override func removeObject(forKey defaultName: String) { write(defaultName, nil) }

    public override func dictionaryRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values.mapValues { stored -> Any in
            switch stored {
            case .data(let data): data
            case .bool(let value): value
            }
        }
    }

    public override func synchronize() -> Bool { true }

    public override func removePersistentDomain(forName domainName: String) {
        lock.lock()
        values = [:]
        lock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
#endif
