#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK

/// The secret that keys the names of the application's pipes (DECISIONS.md D-010): 32 random bytes in `pipe.key`
/// beside the socket path, made once with `CREATE_NEW` and a DACL that lets only this user in, whatever the folder
/// would give it. It is never logged. A process that cannot read it does not connect, and the hook leaves the request
/// to the client's own prompt.
enum PipeKey {
    static let fileName = "pipe.key"
    static let length = 32

    /// The key in `folder`; with `creating`, made when there is none.
    static func read(in folder: URL, creating: Bool) -> [UInt8]? {
        let path = folder.appendingPathComponent(fileName).path.replacingOccurrences(of: "/", with: "\\")
        if let key = load(path) { return key }
        guard creating else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var generator = SystemRandomNumberGenerator()
        let key = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
        guard let security = try? Win32.OwnerOnlySecurity() else { return nil }
        let handle = security.withAttributes { attributes in
            Win32.withWide(path) {
                CreateFileW($0, DWORD(GENERIC_WRITE), 0, attributes, DWORD(CREATE_NEW), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
            }
        }
        guard let handle, handle != Win32.invalidHandle else {
            // Another process of this user made it first: that one is the key.
            return GetLastError() == DWORD(ERROR_FILE_EXISTS) ? load(path) : nil
        }
        var written: DWORD = 0
        let saved = WriteFile(handle, key, DWORD(key.count), &written, nil) && written == DWORD(key.count)
        FlushFileBuffers(handle)
        CloseHandle(handle)
        return saved ? key : nil
    }

    private static func load(_ path: String) -> [UInt8]? {
        let handle = Win32.withWide(path) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return nil }
        defer { CloseHandle(handle) }
        var key = [UInt8](repeating: 0, count: length + 1)
        var count: DWORD = 0
        guard ReadFile(handle, &key, DWORD(key.count), &count, nil), count == DWORD(length) else { return nil }
        return Array(key.prefix(length))
    }
}

/// HMAC (RFC 2104) over the portable SHA-256.
enum PortableHMAC {
    static func sha256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let block = 64
        var key = key.count > block ? PortableSHA256.digest(key) : key
        key += [UInt8](repeating: 0, count: block - key.count)
        let inner = PortableSHA256.digest(key.map { $0 ^ 0x36 } + message)
        return PortableSHA256.digest(key.map { $0 ^ 0x5c } + inner)
    }
}
#endif
