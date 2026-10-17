#if os(Windows)
import Foundation

// POSIX names the shared tests use to drive the code over plain descriptors, given their macOS meaning on the C
// runtime's descriptors. Test-only; the product has its own (Sources/AgentHUDCore/Platform/Windows).

/// The tests call `Darwin.pipe(_:)` by its module's name.
enum Darwin {
    /// A binary, non-inherited anonymous pipe, as `pipe(2)`: the read end first.
    static func pipe(_ ends: UnsafeMutablePointer<Int32>) -> Int32 {
        _pipe(ends, 1024 * 1024, _O_BINARY | _O_NOINHERIT)
    }
}

/// `write(2)` with the byte count as an `Int`.
@discardableResult
func write(_ descriptor: Int32, _ bytes: UnsafeRawPointer?, _ count: Int) -> Int {
    Int(_write(descriptor, bytes, UInt32(count)))
}
#endif
