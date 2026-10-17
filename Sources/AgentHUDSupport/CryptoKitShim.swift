#if !canImport(CryptoKit)
import Foundation

// Where CryptoKit does not exist (Windows), the few CryptoKit calls the package makes — `SHA256.hash(data:)` and
// `Insecure.SHA1.hash(data:)` — resolve to these, so the files that make them only guard their import. On Apple
// platforms this file compiles to nothing and CryptoKit is used as before (docs/windows-port/adr/ADR-004-sha256.md).

/// A digest's bytes, iterable like CryptoKit's digests.
public struct PortableDigest: Sequence, Sendable, Hashable {
    public let bytes: [UInt8]
    public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
}

public enum SHA256 {
    public static func hash<D: DataProtocol>(data: D) -> PortableDigest { PortableDigest(bytes: PortableSHA256.digest(data)) }
}

public enum Insecure {
    public enum SHA1 {
        public static func hash<D: DataProtocol>(data: D) -> PortableDigest { PortableDigest(bytes: PortableSHA1.digest(data)) }
    }
}
#endif
