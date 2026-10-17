#if os(Windows)
import Foundation
import WinSDK

/// Generic credentials in the Windows Credential Manager, read in memory only.
///
/// The GitHub CLI keeps its token through go-keyring, which on Windows writes a generic credential whose target is
/// `<service>:<user>` and whose blob is the secret's UTF-8 bytes (zalando/go-keyring `keyring_windows.go`); `gh` uses the
/// service `gh:<host>` and an empty user for the active account (cli/cli `internal/config`), so the active token of
/// github.com is the credential `gh:github.com:` (docs/windows-port/SUPPORT_MATRIX.md).
enum WindowsCredentials {
    /// The secret of the generic credential whose target is exactly `target`, as UTF-8; nil when there is none.
    static func genericSecret(target: String) -> String? {
        var credential: PCREDENTIALW?
        let found = Win32.withWide(target) { CredReadW($0, DWORD(CRED_TYPE_GENERIC), 0, &credential) }
        guard found, let credential else { return nil }
        defer { CredFree(credential) }
        let size = Int(credential.pointee.CredentialBlobSize)
        guard size > 0, size <= 64 * 1024, let blob = credential.pointee.CredentialBlob else { return nil }
        return String(decoding: UnsafeBufferPointer(start: blob, count: size), as: UTF8.self)
    }
}

extension CopilotCredentials {
    /// The token go-keyring keeps for `service` and the active (empty) user: what the keychain item of that service is
    /// on macOS.
    static func genericPassword(service: String) -> String? {
        WindowsCredentials.genericSecret(target: service + ":")
    }
}
#endif
