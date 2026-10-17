import Foundation

/// How a client's executable is found: at the places its installers use first, since an application started from
/// Finder gets a minimal `PATH`, then in the directories of `PATH`.
@usableFromInline
enum Executables {
    /// `name` in each directory of `path`, in order.
    static func onPath(_ name: String, path: String) -> [URL] {
        #if os(Windows)
        WindowsExecutables.onPath(name, path: path)
        #else
        path.split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
        #endif
    }

    /// The first of `candidates` that can run.
    static func first(_ candidates: [URL], fileManager: FileManager = .default) -> URL? {
        #if os(Windows)
        candidates.lazy.compactMap(WindowsExecutables.program).first
        #else
        candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
        #endif
    }

    /// This process's `PATH`.
    @usableFromInline static var systemPath: String { path(in: ProcessInfo.processInfo.environment) }

    /// The `PATH` of `environment`; on Windows, whatever the variable's case (`Path` there).
    static func path(in environment: [String: String]) -> String {
        #if os(Windows)
        environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        #else
        environment["PATH"] ?? ""
        #endif
    }
}
