#if os(Windows)
import Foundation
import WinSDK

/// Tells what changed under a set of directories since the previous check, using `ReadDirectoryChangesW`: the Windows
/// counterpart of the FSEvents monitor, with the same rules. Each directory is watched recursively; a notification
/// buffer that overflowed, a watch that failed and the first check all count as dropped events, after which everything
/// must be scanned. Directories created later are watched after the next `update()`.
final class FileChangeMonitor {
    /// Shared with the watch threads, which can still be finishing while the monitor is being released.
    private final class Changes: @unchecked Sendable {
        struct State {
            var changed = true
            /// Files reported since the last check; nil when events were dropped or not yet seen, so everything must be scanned.
            var paths: Set<String>? = nil
        }
        static let pathLimit = 10_000
        private let lock = NSLock()
        private var state = State()
        /// Called on a watch thread after every batch of events, so a waiting reader can wake at once.
        let onChange: (@Sendable () -> Void)?
        init(onChange: (@Sendable () -> Void)?) { self.onChange = onChange }

        func withLock<Result>(_ body: (inout State) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }

        func record(_ paths: [String]?) {
            withLock { state in
                state.changed = true
                guard let paths, var known = state.paths else { state.paths = nil; return }
                known.formUnion(paths)
                state.paths = known.count > Changes.pathLimit ? nil : known
            }
            onChange?()
        }
    }

    /// One directory's watch: a thread waiting on the directory's change notifications or on being stopped.
    private final class Watch: @unchecked Sendable {
        let directory: String
        private let handle: HANDLE
        private let stopEvent: HANDLE
        private let changes: Changes
        private let lock = NSLock()
        private var ended = false

        init?(directory: String, changes: Changes) {
            let opened = Win32.withWide(directory.replacingOccurrences(of: "/", with: "\\")) {
                CreateFileW($0, DWORD(FILE_LIST_DIRECTORY),
                            DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE), nil,
                            DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS) | DWORD(FILE_FLAG_OVERLAPPED), nil)
            }
            guard let opened, opened != Win32.invalidHandle, let stopEvent = CreateEventW(nil, true, false, nil) else {
                if let opened, opened != Win32.invalidHandle { CloseHandle(opened) }
                return nil
            }
            self.directory = directory
            handle = opened
            self.stopEvent = stopEvent
            self.changes = changes
            let thread = Thread { [self] in run() }
            thread.name = "app.agenthud.file-changes"
            thread.qualityOfService = .utility
            thread.start()
        }

        /// Whether the watch stopped by itself, as when its directory was removed or renamed.
        var hasEnded: Bool {
            lock.lock()
            defer { lock.unlock() }
            return ended
        }

        func stop() { SetEvent(stopEvent) }

        private func run() {
            defer {
                CloseHandle(handle)
                CloseHandle(stopEvent)
                lock.lock()
                ended = true
                lock.unlock()
            }
            guard let overlapped = Overlapped() else { return changes.record(nil) }
            let size = 64 * 1024
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
            defer { buffer.deallocate() }
            let filter = DWORD(FILE_NOTIFY_CHANGE_FILE_NAME) | DWORD(FILE_NOTIFY_CHANGE_DIR_NAME)
                | DWORD(FILE_NOTIFY_CHANGE_SIZE) | DWORD(FILE_NOTIFY_CHANGE_LAST_WRITE) | DWORD(FILE_NOTIFY_CHANGE_CREATION)
            while true {
                overlapped.reset()
                guard ReadDirectoryChangesW(handle, buffer, DWORD(size), true, filter, nil, overlapped.pointer, nil) else {
                    // The directory went away or cannot be watched any more: what changed is unknown.
                    return changes.record(nil)
                }
                var events: [HANDLE?] = [overlapped.event, stopEvent]
                let status = WaitForMultipleObjects(2, &events, false, INFINITE)
                guard status == WAIT_OBJECT_0 else {
                    CancelIoEx(handle, overlapped.pointer)
                    var ignored: DWORD = 0
                    _ = GetOverlappedResult(handle, overlapped.pointer, &ignored, true)
                    return
                }
                var count: DWORD = 0
                guard GetOverlappedResult(handle, overlapped.pointer, &count, false) else { return changes.record(nil) }
                // A watched directory being removed can still report a last batch: once it is gone, what changed under
                // it is unknown, and the handle goes at once so that a client can make a directory of that name again.
                guard WindowsFiles.attributes(directory) != nil else { return changes.record(nil) }
                // No bytes: the system's buffer overflowed and the events were dropped.
                changes.record(count == 0 ? nil : Self.paths(in: buffer, count: Int(count), directory: directory))
            }
        }

        /// The full paths a batch of `FILE_NOTIFY_INFORMATION` records names, written as Foundation writes paths.
        static func paths(in buffer: UnsafeMutableRawPointer, count: Int, directory: String) -> [String] {
            var paths: [String] = []
            var offset = 0
            while offset + MemoryLayout<FILE_NOTIFY_INFORMATION>.size <= count {
                let record = buffer.advanced(by: offset)
                let next = Int(record.load(fromByteOffset: 0, as: DWORD.self))
                let nameLength = Int(record.load(fromByteOffset: 8, as: DWORD.self)) / 2
                let name = record.advanced(by: 12).assumingMemoryBound(to: UInt16.self)
                let relative = String(decoding: UnsafeBufferPointer(start: name, count: nameLength), as: UTF16.self)
                paths.append(directory + "/" + relative.replacingOccurrences(of: "\\", with: "/"))
                guard next > 0 else { break }
                offset += next
            }
            return paths
        }
    }

    private let directories: [String]
    private let changes: Changes
    private var watches: [Watch] = []
    private var watched: [String]?

    /// - onChange: called after each batch of file events, on a watch thread.
    init(directories: [URL], onChange: (@Sendable () -> Void)? = nil) {
        // Watches are recursive, so a directory inside another one adds nothing. Windows paths compare without case.
        let paths = Set(directories.map { $0.standardizedFileURL.path })
        self.directories = paths.filter { path in
            !paths.contains { $0 != path && path.lowercased().hasPrefix($0.lowercased() + "/") }
        }.sorted()
        changes = Changes(onChange: onChange)
        update()
    }

    /// False when no watched directory exists or no watch could be started, so sources must be read on a schedule.
    var isWatching: Bool { watched.map { !$0.isEmpty } ?? false }

    deinit { stopWatches() }

    /// Watches the directories that exist now; a change in the watched set, or a watch that ended by itself, counts as
    /// a change of everything.
    func update() {
        let existing = directories.filter { FileManager.default.fileExists(atPath: $0) }
        guard existing != watched || watches.contains(where: \.hasEnded) else { return }
        stopWatches()
        watched = existing
        changes.withLock { $0 = .init() }
        guard !existing.isEmpty else { return }
        watches = existing.compactMap { Watch(directory: $0, changes: changes) }
        if watches.count != existing.count {
            stopWatches()
            watched = nil
        }
    }

    /// Whether anything changed since the previous call. Without a working watch every call reports a change.
    func consumeChanges() -> Bool {
        let changed = changes.withLock { state in
            let changed = state.changed
            state.changed = false
            state.paths = []
            return changed
        }
        return changed || !isWatching
    }

    /// Files reported since the previous call, or nil when a full scan is needed: the first call, dropped events,
    /// a newly watched directory, or no working watch.
    func consumePaths() -> Set<String>? {
        let paths = changes.withLock { state in
            let paths = state.paths
            state.changed = false
            state.paths = []
            return paths
        }
        return isWatching ? paths : nil
    }

    private func stopWatches() {
        watches.forEach { $0.stop() }
        watches = []
    }
}
#endif
