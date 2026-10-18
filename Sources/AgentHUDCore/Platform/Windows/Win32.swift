#if os(Windows)
import Foundation
import WinSDK

/// Small helpers over the Win32 API that the Windows implementations share: wide strings, the last error, the current
/// user's SID and a security descriptor that lets only that user in (docs/windows-port/PORTING_PLAN.md).
enum Win32 {
    /// A Win32 error with the code `GetLastError` gave and the call that failed; its description names both and never
    /// anything the call carried.
    struct Failure: Error, CustomStringConvertible {
        let call: String
        let code: DWORD
        init(_ call: String, code: DWORD = GetLastError()) {
            self.call = call
            self.code = code
        }
        var description: String { "\(call) failed with Windows error \(code)" }
    }

    /// `body` with `string` as a NUL-terminated UTF-16 string.
    static func withWide<Result>(_ string: String, _ body: (UnsafePointer<WCHAR>) throws -> Result) rethrows -> Result {
        let wide = Array(string.utf16) + [0]
        return try wide.withUnsafeBufferPointer { try body($0.baseAddress!) }
    }

    /// The string a NUL-terminated UTF-16 buffer holds.
    static func string(_ pointer: UnsafePointer<WCHAR>) -> String {
        String(decodingCString: pointer, as: UTF16.self)
    }

    /// The SID of the user this process runs as, as `S-1-5-21-…`; nil when the token cannot be read.
    static let currentUserSID: String? = {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { return nil }
        defer { CloseHandle(token) }
        return userSID(ofToken: token)
    }()

    /// The string form of `sid`, `S-1-5-…`.
    static func sidString(_ sid: PSID) -> String? {
        var text: LPWSTR?
        guard ConvertSidToStringSidW(sid, &text), let text else { return nil }
        defer { LocalFree(text) }
        return string(text)
    }

    /// Whether the open file is the current user's and no one else is let in: owned by this user, with a DACL whose
    /// every allowing entry names this user (a missing DACL lets everyone in, so it fails).
    static func isOwnerOnly(_ handle: HANDLE) -> Bool {
        guard let me = currentUserSID else { return false }
        var owner: PSID?
        var dacl: PACL?
        var descriptor: PSECURITY_DESCRIPTOR?
        let wanted = SECURITY_INFORMATION(OWNER_SECURITY_INFORMATION) | SECURITY_INFORMATION(DACL_SECURITY_INFORMATION)
        guard GetSecurityInfo(handle, SE_FILE_OBJECT, wanted, &owner, nil, &dacl, nil, &descriptor) == DWORD(ERROR_SUCCESS),
              let descriptor else { return false }
        defer { LocalFree(descriptor) }
        guard let owner, sidString(owner) == me, let dacl else { return false }
        for index in 0..<DWORD(dacl.pointee.AceCount) {
            var entry: LPVOID?
            guard GetAce(dacl, index, &entry), let entry else { return false }
            let type = entry.assumingMemoryBound(to: ACE_HEADER.self).pointee.AceType
            if type == BYTE(ACCESS_DENIED_ACE_TYPE) { continue }
            guard type == BYTE(ACCESS_ALLOWED_ACE_TYPE) else { return false }
            // ACCESS_ALLOWED_ACE: the header, the mask, then the SID.
            let sid = entry.advanced(by: MemoryLayout<ACE_HEADER>.size + MemoryLayout<ACCESS_MASK>.size)
            guard sidString(sid) == me else { return false }
        }
        return true
    }

    /// The user SID string of `token`.
    static func userSID(ofToken token: HANDLE) -> String? {
        var size: DWORD = 0
        _ = GetTokenInformation(token, TokenUser, nil, 0, &size)
        guard size > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<TOKEN_USER>.alignment)
        defer { buffer.deallocate() }
        guard GetTokenInformation(token, TokenUser, buffer, size, &size) else { return nil }
        let user = buffer.assumingMemoryBound(to: TOKEN_USER.self).pointee
        var text: LPWSTR?
        guard ConvertSidToStringSidW(user.User.Sid, &text), let text else { return nil }
        defer { LocalFree(text) }
        return string(text)
    }

    /// The user SID of the process `pid`; nil when it cannot be opened, such as another user's process.
    static func userSID(ofProcess pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(process) }
        var token: HANDLE?
        guard OpenProcessToken(process, DWORD(TOKEN_QUERY), &token), let token else { return nil }
        defer { CloseHandle(token) }
        return userSID(ofToken: token)
    }

    /// A security descriptor whose owner is the current user and whose protected DACL grants that user alone full
    /// access: not Administrators, not SYSTEM, no inherited entries. What a unix socket's mode 0700 is on macOS.
    final class OwnerOnlySecurity {
        private var descriptor: PSECURITY_DESCRIPTOR?
        private(set) var attributes = SECURITY_ATTRIBUTES()

        init() throws {
            guard let sid = Win32.currentUserSID else { throw Failure("OpenProcessToken") }
            let sddl = "O:\(sid)D:P(A;;GA;;;\(sid))"
            var descriptor: PSECURITY_DESCRIPTOR?
            let converted = Win32.withWide(sddl) {
                ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
            }
            guard converted, let descriptor else { throw Failure("ConvertStringSecurityDescriptorToSecurityDescriptorW") }
            self.descriptor = descriptor
            attributes.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
            attributes.lpSecurityDescriptor = descriptor
            attributes.bInheritHandle = false
        }

        deinit { if let descriptor { LocalFree(descriptor) } }

        func withAttributes<Result>(_ body: (UnsafeMutablePointer<SECURITY_ATTRIBUTES>) throws -> Result) rethrows -> Result {
            try withUnsafeMutablePointer(to: &attributes) { try body($0) }
        }
    }

    /// A known folder's path, such as `FOLDERID_RoamingAppData`; nil when the shell cannot name it.
    static func knownFolder(_ id: KNOWNFOLDERID) -> URL? {
        var id = id
        var path: PWSTR?
        guard SHGetKnownFolderPath(&id, DWORD(KF_FLAG_DEFAULT.rawValue), nil, &path) == S_OK, let path else { return nil }
        defer { CoTaskMemFree(path) }
        return URL(fileURLWithPath: string(path), isDirectory: true)
    }

    /// `path` in its long form, every 8.3 name spelled out (`GetLongPathNameW`), or as given when it does not exist or has none.
    /// A path longer than `MAX_PATH` is asked for in its `\\?\` form and given back without it.
    static func longPath(_ path: String) -> String {
        let unprefixed = Win32.unprefixed(path)
        let asked: String
        if unprefixed.utf16.count < Int(MAX_PATH) { asked = unprefixed }
        else if unprefixed.hasPrefix(#"\\"#) { asked = #"\\?\UNC\"# + unprefixed.dropFirst(2) }
        else { asked = #"\\?\"# + unprefixed }
        let length = Win32.withWide(asked) { GetLongPathNameW($0, nil, 0) }
        guard length > 0 else { return path }
        var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
        let written = Win32.withWide(asked) { GetLongPathNameW($0, &buffer, DWORD(buffer.count)) }
        guard written > 0, Int(written) < buffer.count else { return path }
        return Win32.unprefixed(String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self))
    }

    /// `path` without a `\\?\` prefix: `\\?\C:\…` as `C:\…`, `\\?\UNC\server\share` as `\\server\share`.
    static func unprefixed(_ path: String) -> String {
        if path.hasPrefix(#"\\?\UNC\"#) { return #"\\"# + path.dropFirst(8) }
        if path.hasPrefix(#"\\?\"#) { return String(path.dropFirst(4)) }
        return path
    }

    /// The value of the environment variable `name` when it is set and not blank, its name matched without regard to
    /// case as Windows matches it (`ProcessInfo.environment` is keyed by the spelling the variable was set with, and a
    /// process may inherit `SYSTEMROOT` or `Path`).
    static func environment(_ name: String) -> String? {
        withWide(name) { key -> String? in
            let size = GetEnvironmentVariableW(key, nil, 0)
            guard size > 0 else { return nil }
            var buffer = [WCHAR](repeating: 0, count: Int(size))
            let count = GetEnvironmentVariableW(key, &buffer, size)
            guard count > 0, count < size else { return nil }
            let value = String(decoding: buffer[..<Int(count)], as: UTF16.self)
            return value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
        }
    }

    static var invalidHandle: HANDLE? { HANDLE(bitPattern: -1) }

    /// `SECURITY_IDENTIFICATION` (`SecurityIdentification << 16`), a macro the importer does not bring over: a client
    /// that opens a pipe with it lets the server learn who it is and nothing more.
    static let securityIdentification = DWORD(SecurityIdentification.rawValue) << 16

    /// A handle that crosses to another thread with the one owner that uses it there.
    struct SendableHandle: @unchecked Sendable {
        let handle: HANDLE
    }
}
#endif
