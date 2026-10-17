import Foundation

/// A Git repository, shared by its worktrees, or the recorded directory when it is outside Git.
public enum SessionProject: Hashable, Sendable {
    case directory(String)
    case unassigned

    public init(_ session: LiveSession) {
        if let path = session.workingDirectory, !path.isEmpty { self = .directory(Self.directory(for: path)) }
        else { self = .unassigned }
        #if os(Windows)
        // A repository is named by its real path, so sessions whose folders differ only in case share it; a recorded
        // directory outside Git keeps its spelling.
        if case .directory(let project) = self,
           FileManager.default.fileExists(atPath: URL(fileURLWithPath: project).appendingPathComponent(".git").path),
           let real = WindowsPaths.finalPath(project) {
            self = .directory(real)
        }
        #endif
    }

    public var path: String? {
        if case .directory(let path) = self { return path }
        return nil
    }

    public var title: String {
        path.map { ($0 as NSString).lastPathComponent } ?? L10n.text("未归属项目", "Unassigned project")
    }

    public var label: String {
        path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? L10n.text("未归属项目", "Unassigned project")
    }

    /// Read Git's own pointers instead of inferring a repository from a folder name or a worktree location.
    private static func directory(for path: String) -> String {
        #if os(Windows)
        // swift-corelibs-foundation standardizes a drive's root (`C:/`) into a path on the current drive (`E:/C:`).
        if WindowsPaths.isRootOrRelative(path) { return path }
        #endif
        var directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        while true {
            let marker = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return directory.path }
                guard let pointer = try? String(contentsOf: marker, encoding: .utf8), pointer.hasPrefix("gitdir:") else { return path }
                guard let gitDirectory = resolve(String(pointer.dropFirst("gitdir:".count)), relativeTo: directory) else { return path }
                // Submodules and separate Git directories have no commondir: their checkout stays its own project.
                guard let common = try? String(contentsOf: gitDirectory.appendingPathComponent("commondir"), encoding: .utf8) else {
                    return directory.path
                }
                guard let commonDirectory = resolve(common, relativeTo: gitDirectory) else { return path }
                return commonDirectory.lastPathComponent == ".git" ? commonDirectory.deletingLastPathComponent().path : commonDirectory.path
            }
            // Legacy Foundation appends ".." when deleting the root's last component.
            if directory.path == "/" { return path }
            #if os(Windows)
            // Above a drive's or share's root Foundation's paths turn relative, which would resolve against the
            // working directory.
            if WindowsPaths.isRootOrRelative(directory.path) { return path }
            #endif
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return path }
            directory = parent
        }
    }

    private static func resolve(_ pointer: String, relativeTo directory: URL) -> URL? {
        let path = pointer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true, relativeTo: directory)
            .standardizedFileURL.resolvingSymlinksInPath()
    }
}
