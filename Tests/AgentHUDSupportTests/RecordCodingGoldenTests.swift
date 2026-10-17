import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import AgentHUDSupport

// Cross-platform determinism (docs/windows-port/adr/ADR-004-sha256.md): record ids, digests, encoder output and
// millisecond dates must come out byte for byte the same on macOS, which hashes with CryptoKit, and on Windows, which
// hashes with PortableSHA256. The expected values in the fixture were computed with Python's hashlib
// (scripts/make-record-coding-golden.py), and both CI runs check them.

private struct Golden: Decodable {
    struct RecordHash: Decodable { let components: [String]; let hash: String }
    struct Digest: Decodable {
        let utf8: String?
        let `repeat`: String?
        let count: Int?
        let hex: String
        let base64: String?
        var message: Data {
            if let utf8 { return Data(utf8.utf8) }
            return Data(String(repeating: `repeat` ?? "", count: count ?? 0).utf8)
        }
    }
    let recordHashes: [RecordHash]
    let sha256: [Digest]
    let sha1: [Digest]
    let milliseconds: [Int64]
    let encoderSample: String

    static func load() throws -> Golden {
        let url = try #require(Bundle.module.url(forResource: "record-coding-golden", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }
}

private func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

@Test func recordIdentitiesMatchTheGoldenSamples() throws {
    let golden = try Golden.load()
    #expect(golden.recordHashes.count >= 10)
    for sample in golden.recordHashes {
        #expect(RecordCoding.hash(sample.components) == sample.hash, "\(sample.components.prefix(3))")
    }
}

@Test func digestsMatchTheNISTVectors() throws {
    let golden = try Golden.load()
    for vector in golden.sha256 {
        #expect(hex(PortableSHA256.digest(vector.message)) == vector.hex, "SHA-256 of \(vector.message.count) bytes")
        #expect(hex(SHA256.hash(data: vector.message)) == vector.hex, "the platform's SHA256")
    }
    for vector in golden.sha1 {
        #expect(hex(PortableSHA1.digest(vector.message)) == vector.hex, "SHA-1 of \(vector.message.count) bytes")
        #expect(hex(Insecure.SHA1.hash(data: vector.message)) == vector.hex, "the platform's SHA-1")
        if let base64 = vector.base64 {
            #expect(Data(PortableSHA1.digest(vector.message)).base64EncodedString() == base64, "RFC 6455 accept key")
        }
    }
}

@Test func millisecondDatesRoundTripTheGoldenSamples() throws {
    for ms in try Golden.load().milliseconds {
        #expect(RecordCoding.milliseconds(RecordCoding.date(ms)) == ms, "\(ms)")
    }
}

@Test func theRecordEncoderWritesTheGoldenSample() throws {
    struct Sample: Encodable {
        let at: Date, count: Int64, flag: Bool, list: [String], name: String, nested: [String: Int], ratio: Double
    }
    let sample = Sample(at: RecordCoding.date(1_700_000_000_123), count: 9_007_199_254_740_993, flag: true, list: ["x"],
                        name: "a/b é中😀 \"q\" \\ \n\t", nested: ["z": 1, "a": 2, "B": 3, "a10": 4, "a2": 5], ratio: 1.5)
    let encoded = String(decoding: try RecordCoding.encoder().encode(sample), as: UTF8.self)
    #expect(encoded == (try Golden.load().encoderSample))
}

#if canImport(CryptoKit)
/// On macOS the portable digests are compared with CryptoKit over every padding boundary and beyond.
@Test func portableDigestsEqualCryptoKit() {
    // A fixed seed, so a failing message can be made again; the failure names its length and draw.
    var generator = SplitMix64(seed: 0x4147_454E_5448_5544)
    for length in 0...300 {
        for draw in 0..<7 {
            let message = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            #expect(PortableSHA256.digest(message) == Array(CryptoKit.SHA256.hash(data: message)), "SHA-256, \(length) bytes, draw \(draw)")
            #expect(PortableSHA1.digest(message) == Array(Insecure.SHA1.hash(data: message)), "SHA-1, \(length) bytes, draw \(draw)")
        }
    }
}

/// SplitMix64 (Steele, Lea and Flood, 2014): a small seeded generator for reproducible test input.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
