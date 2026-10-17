import Foundation

/// SHA-256 (FIPS 180-4) without CryptoKit, for platforms that have none. Record ids must be identical on every machine,
/// so the macOS tests compare it with CryptoKit byte for byte and both platforms check the NIST vectors
/// (docs/windows-port/adr/ADR-004-sha256.md).
package enum PortableSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// The 32-byte digest of `data`.
    package static func digest<D: DataProtocol>(_ data: D) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var w = [UInt32](repeating: 0, count: 64)
        PortableDigestBlocks.forEachBlock(of: data) { block in
            for t in 0..<16 { w[t] = block[t] }
            for t in 16..<64 {
                let s0 = w[t - 15].rotatedRight(7) ^ w[t - 15].rotatedRight(18) ^ (w[t - 15] >> 3)
                let s1 = w[t - 2].rotatedRight(17) ^ w[t - 2].rotatedRight(19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for t in 0..<64 {
                let s1 = e.rotatedRight(6) ^ e.rotatedRight(11) ^ e.rotatedRight(25)
                let choice = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ choice &+ k[t] &+ w[t]
                let s0 = a.rotatedRight(2) ^ a.rotatedRight(13) ^ a.rotatedRight(22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ majority
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.flatMap(\.bigEndianBytes)
    }
}

/// SHA-1 (FIPS 180-4) without CryptoKit, only for protocols that require it, such as a WebSocket handshake's
/// `Sec-WebSocket-Accept` (RFC 6455). Never used for identities.
package enum PortableSHA1 {
    /// The 20-byte digest of `data`.
    package static func digest<D: DataProtocol>(_ data: D) -> [UInt8] {
        var h: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]
        var w = [UInt32](repeating: 0, count: 80)
        PortableDigestBlocks.forEachBlock(of: data) { block in
            for t in 0..<16 { w[t] = block[t] }
            for t in 16..<80 { w[t] = (w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16]).rotatedLeft(1) }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for t in 0..<80 {
                let f: UInt32, k: UInt32
                switch t {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5a827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ed9eba1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc
                default: f = b ^ c ^ d; k = 0xca62c1d6
                }
                let temp = a.rotatedLeft(5) &+ f &+ e &+ k &+ w[t]
                e = d; d = c; c = b.rotatedLeft(30); b = a; a = temp
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d; h[4] = h[4] &+ e
        }
        return h.flatMap(\.bigEndianBytes)
    }
}

/// The Merkle–Damgård padding SHA-1 and SHA-256 share: the message, a 1 bit, zeros, and its length in bits as a 64-bit
/// big-endian number, cut into 512-bit blocks of sixteen big-endian words.
enum PortableDigestBlocks {
    static func forEachBlock<D: DataProtocol>(of data: D, _ body: ([UInt32]) -> Void) {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
        var block = [UInt32](repeating: 0, count: 16)
        for start in stride(from: 0, to: message.count, by: 64) {
            for t in 0..<16 {
                let i = start + t * 4
                block[t] = UInt32(message[i]) << 24 | UInt32(message[i + 1]) << 16 | UInt32(message[i + 2]) << 8 | UInt32(message[i + 3])
            }
            body(block)
        }
    }
}

private extension UInt32 {
    func rotatedRight(_ n: UInt32) -> UInt32 { (self >> n) | (self << (32 - n)) }
    func rotatedLeft(_ n: UInt32) -> UInt32 { (self << n) | (self >> (32 - n)) }
    var bigEndianBytes: [UInt8] {
        [UInt8(truncatingIfNeeded: self >> 24), UInt8(truncatingIfNeeded: self >> 16),
         UInt8(truncatingIfNeeded: self >> 8), UInt8(truncatingIfNeeded: self)]
    }
}
