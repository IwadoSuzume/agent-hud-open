#if os(Windows)
import AgentHUDSupport
import Foundation

/// Codex Desktop's local IPC on Windows.
///
/// On macOS the HUD reads Codex Desktop's pending Computer Use and browser approvals and its mid-turn questions through
/// `$CODEX_HOME/ipc/ipc.sock`. Where the Windows build of Codex Desktop keeps that channel, and whether it is a named
/// pipe or an AF_UNIX socket, is not documented, so the Windows build does not connect to it: every connection reports
/// `unavailable`, as a Mac without Desktop running does, and the observers that use it read nothing
/// (docs/windows-port/SUPPORT_MATRIX.md). The class keeps the macOS API so the shared observers build unchanged.
public final class CodexDesktopIPC {
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible, LoggableFailure {
        case invalidInput, unavailable, timedOut, protocolError
        case rejected(String)
        /// The submission may have been accepted. Do not automatically resend it.
        case acceptanceUncertain

        /// The case and the reason Desktop gave, if any, for a log.
        public var description: String {
            switch self {
            case .invalidInput: "invalidInput: the request to Desktop was not well formed"
            case .unavailable: "unavailable: Desktop's socket was missing or the connection closed"
            case .timedOut: "timedOut: Desktop did not reply in time"
            case .protocolError: "protocolError: Desktop's reply was not in the form expected"
            case .rejected(let reason): "rejected: Desktop refused the request with \"\(reason)\""
            case .acceptanceUncertain: "acceptanceUncertain: the request was sent but Desktop did not confirm it"
            }
        }
    }

    public init(path: String, timeout: TimeInterval) throws { throw Failure.unavailable }

    public func close() {}

    public func request(method: String, version: Int, source: String, target: String? = nil,
                        params: [String: Any], didWrite: (() -> Void)? = nil) throws -> [String: Any] {
        throw Failure.unavailable
    }

    public func conversationSnapshot(source: String, owner: String, threadID: String) throws -> [String: Any] {
        throw Failure.unavailable
    }

    public func conversationState(source: String, owner: String, threadID: String) throws -> JSONValue {
        throw Failure.unavailable
    }

    public func follow(_ value: Bool, source: String, owner: String, threadID: String) throws { throw Failure.unavailable }

    public func renew(timeout: TimeInterval) {}

    public func waitForMessage(_ seconds: TimeInterval) throws -> Bool { throw Failure.unavailable }

    public func message(limit: Int) throws -> Data { throw Failure.unavailable }

    public func post(_ message: [String: Any]) throws { throw Failure.unavailable }

    public func declines(_ message: JSONValue) throws -> Bool { throw Failure.unavailable }
}
#endif
