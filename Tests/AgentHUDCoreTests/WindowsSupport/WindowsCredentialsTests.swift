#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// Credential Manager reads (`Platform/Windows/WindowsCredentials.swift`), against fixture credentials this test writes
/// under a target of its own, `agenthud-test-<UUID>`, kept for the logon session only and deleted when each test ends
/// (DECISIONS.md D-039). No real credential is read: no `gh:` target is ever asked for.
final class WindowsCredentialsTests: XCTestCase {
    private var service: String!

    override func setUp() {
        service = "agenthud-test-\(UUID().uuidString)"
    }

    /// Writes a generic credential with target `target` and `blob` as its secret, as go-keyring writes gh's token.
    private func write(_ blob: [UInt8], target: String, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { _ = Win32.withWide(target) { CredDeleteW($0, DWORD(CRED_TYPE_GENERIC), 0) } }
        var bytes = blob
        let written = Win32.withWide(target) { name in
            bytes.withUnsafeMutableBufferPointer { secret in
                var credential = CREDENTIALW()
                credential.Type = DWORD(CRED_TYPE_GENERIC)
                credential.TargetName = UnsafeMutablePointer(mutating: name)
                credential.CredentialBlobSize = DWORD(secret.count)
                credential.CredentialBlob = secret.baseAddress
                credential.Persist = DWORD(CRED_PERSIST_SESSION)
                return CredWriteW(&credential, 0)
            }
        }
        XCTAssertTrue(written, "CredWriteW failed: \(GetLastError())", file: file, line: line)
    }

    func testTheActiveAccountsTokenIsReadFromTheServicesEmptyUser() {
        XCTAssertNil(CopilotCredentials.genericPassword(service: service), "nothing there yet")
        let token = "gho_fixture-令牌-✓"
        write(Array(token.utf8), target: service + ":")
        XCTAssertEqual(CopilotCredentials.genericPassword(service: service), token)
        XCTAssertEqual(WindowsCredentials.genericSecret(target: service + ":"), token)
    }

    func testAnotherUsersCredentialIsNotTheActiveAccount() {
        write(Array("gho_other".utf8), target: service + ":someone")
        XCTAssertNil(CopilotCredentials.genericPassword(service: service), "only `<service>:` is the active account")
        XCTAssertNil(WindowsCredentials.genericSecret(target: service), "the target is matched exactly")
    }

    func testASecretThatIsNotUTF8OrIsEmptyIsNoToken() {
        write([0x67, 0x68, 0xFF, 0xFE], target: service + ":")
        XCTAssertNil(CopilotCredentials.genericPassword(service: service), "as on macOS, bytes that are not UTF-8 give nothing")
        let empty = "agenthud-test-\(UUID().uuidString)"
        write([], target: empty + ":")
        XCTAssertNil(CopilotCredentials.genericPassword(service: empty))
    }
}
#endif
