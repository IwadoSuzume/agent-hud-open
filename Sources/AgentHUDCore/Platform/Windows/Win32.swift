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

    /// The value of the environment variable `name` when it is set and not blank.
    static func environment(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name],
              !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
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
