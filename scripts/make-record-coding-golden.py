"""Writes Tests/AgentHUDSupportTests/Fixtures/record-coding-golden.json from Python's hashlib (an implementation
independent of both CryptoKit and the port's PortableDigest)."""
import base64
import hashlib
import json
import sys


def rc_hash(components):
    data = b"".join(f"{len(c.encode('utf-8'))}:".encode() + c.encode("utf-8") for c in components)
    return hashlib.sha256(data).hexdigest()


ids = [
    [], [""], ["", ""], ["a"], ["ab", "c"], ["a", "bc"],
    ["claude", "session-1", "2026-10-16T09:41:00.123Z"],
    ["codex", "C:\\Users\\张三\\.codex\\sessions\\rollout.jsonl", "42"],
    ["é中😀", "\u0000", "line\nbreak", "tab\t", "\"quoted\""],
    ["x" * 1000],
    [str(i) for i in range(64)],
]
messages = [b"", b"abc", b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"]
websocket = b"dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
fixture = {
    "about": "Golden samples for RecordCoding and the portable digests (docs/windows-port/adr/ADR-004-sha256.md). "
             "Digests were computed with Python's hashlib, and equal the published examples (FIPS 180-2 appendices, "
             "RFC 6455 section 1.3); the same tests check them against CryptoKit on macOS and against the portable "
             "implementation on Windows.",
    "recordHashes": [{"components": c, "hash": rc_hash(c)} for c in ids],
    "sha256": [{"utf8": m.decode(), "hex": hashlib.sha256(m).hexdigest()} for m in messages]
    + [{"repeat": "a", "count": 1_000_000, "hex": hashlib.sha256(b"a" * 1_000_000).hexdigest()}],
    "sha1": [{"utf8": m.decode(), "hex": hashlib.sha1(m).hexdigest()} for m in messages]
    + [{"repeat": "a", "count": 1_000_000, "hex": hashlib.sha1(b"a" * 1_000_000).hexdigest()},
       {"utf8": websocket.decode(), "hex": hashlib.sha1(websocket).hexdigest(),
        "base64": base64.b64encode(hashlib.sha1(websocket).digest()).decode()}],
    "milliseconds": [0, 1, 999, 1000, 1_700_000_000_123, 1_760_607_660_999, -1, -1_700_000_000_123, 253_402_300_799_999],
}
# RecordCoding.encoder() on the sample RecordCodingGoldenTests builds: sorted keys, no escaped slashes, dates in ms.
sample = {"at": 1_700_000_000_123, "count": 9_007_199_254_740_993, "flag": True, "list": ["x"],
          "name": "a/b é中😀 \"q\" \\ \n\t", "nested": {"z": 1, "a": 2, "B": 3, "a10": 4, "a2": 5}, "ratio": 1.5}
fixture["encoderSample"] = json.dumps(sample, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as out:
    out.write(json.dumps(fixture, ensure_ascii=False, indent=2) + "\n")
print(fixture["sha256"][1]["hex"], fixture["sha1"][-1]["base64"])
