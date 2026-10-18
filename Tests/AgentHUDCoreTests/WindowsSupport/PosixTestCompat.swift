#if os(Windows)
import Foundation
import WinSDK
@testable import AgentHUDCore

// POSIX names the shared tests use to drive the code over plain descriptors, given their macOS meaning on the C
// runtime's descriptors. Test-only; the product has its own (Sources/AgentHUDCore/Platform/Windows).

/// The tests call `Darwin.pipe(_:)` by its module's name.
enum Darwin {
    /// A binary, non-inherited anonymous pipe, as `pipe(2)`: the read end first.
    static func pipe(_ ends: UnsafeMutablePointer<Int32>) -> Int32 {
        _pipe(ends, 1024 * 1024, _O_BINARY | _O_NOINHERIT)
    }
}

/// `close(2)`, by the C runtime's own name for it.
@discardableResult
func close(_ descriptor: Int32) -> Int32 { _close(descriptor) }

/// `recv(2)`'s flag for a read that does not wait.
let MSG_DONTWAIT: Int32 = 0x80

/// `recv(2)` on a descriptor `UnixSocket.connect` returned: one message of the answer (at most `count` bytes of it), 0
/// once the other side closed the connection, -1 with `EAGAIN` when `MSG_DONTWAIT` finds nothing yet.
func recv(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ flags: Int32) -> Int {
    let raw = _get_osfhandle(descriptor)
    guard raw != -1, raw != -2, let handle = HANDLE(bitPattern: raw) else { errno = EBADF; return -1 }
    if flags & MSG_DONTWAIT != 0 {
        var available: DWORD = 0
        guard PeekNamedPipe(handle, nil, 0, nil, &available, nil) else { return 0 }
        if available == 0 { errno = EAGAIN; return -1 }
    }
    switch NamedPipes.readMessage(handle, limit: Int.max / 2) {
    case .message(let data):
        let copied = min(count, data.count)
        data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: copied)
        return copied
    case .closed: return 0
    case .failed: return -1
    }
}

/// `shutdown(2)`'s end for writing. A pipe carries a request as one message, which the server reads whole: there is
/// nothing to half-close, so `shutdown` does nothing.
let SHUT_WR: Int32 = 1
@discardableResult
func shutdown(_ descriptor: Int32, _ how: Int32) -> Int32 { 0 }

/// `pipe(2)` by its bare name, as some tests call it.
func pipe(_ ends: UnsafeMutablePointer<Int32>) -> Int32 { Darwin.pipe(ends) }

/// `arc4random_buf(3)`: `count` random bytes, from the system's generator.
func arc4random_buf(_ buffer: UnsafeMutableRawPointer, _ count: Int) {
    var generator = SystemRandomNumberGenerator()
    for offset in 0..<count { buffer.storeBytes(of: UInt8.random(in: .min ... .max, using: &generator), toByteOffset: offset, as: UInt8.self) }
}

/// `write(2)` with the byte count as an `Int`.
@discardableResult
func write(_ descriptor: Int32, _ bytes: UnsafeRawPointer?, _ count: Int) -> Int {
    Int(_write(descriptor, bytes, UInt32(count)))
}
#endif
