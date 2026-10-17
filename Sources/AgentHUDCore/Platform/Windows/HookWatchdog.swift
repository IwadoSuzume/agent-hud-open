#if os(Windows)
import Foundation
import WinSDK

/// Ends a hook process that is still not done after `seconds`, with status 0 and nothing printed, which leaves the
/// client's own flow as it was: what `alarm(2)` and its handler do in the macOS hook.
final class HookWatchdog: @unchecked Sendable {
    private let cancelled: HANDLE

    init(seconds: Double) {
        cancelled = CreateEventW(nil, true, false, nil)!
        let event = Win32.SendableHandle(handle: cancelled)
        let milliseconds = DWORD(max(1, seconds * 1000))
        let thread = Thread {
            if WaitForSingleObject(event.handle, milliseconds) != WAIT_OBJECT_0 { ExitProcess(0) }
        }
        thread.name = "app.agenthud.hook-watchdog"
        thread.start()
    }

    /// The bounded part is over; the process may now wait as long as its client lets it.
    func cancel() { SetEvent(cancelled) }
}
#endif
