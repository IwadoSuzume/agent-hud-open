#if os(Windows)
import Foundation

extension MCPAppClient {
    /// The call over the application's named pipe: the request is one message, and the reply is read until the
    /// application disconnects, within `timeout` from connecting, as the macOS build reads its socket.
    static func call(_ request: MCPToolRequest, socket path: String, timeout: TimeInterval = timeout) -> Answer {
        guard let descriptor = UnixSocket.connect(to: path) else { return .notRunning }
        defer { _close(descriptor) }
        let message = request.message
        // The application lets go of a longer request without a word, which would read as its not answering.
        guard message.count <= MCPToolRequest.sizeLimit else {
            return .reply(.failure("The call is larger than Agent HUD reads. Send less in one call."))
        }
        let deadline = Date().addingTimeInterval(max(timeout, 0.001))
        guard UnixSocket.send(descriptor, message, until: deadline) else { return .unanswered }
        guard let data = UnixSocket.read(descriptor, limit: replyLimit, until: deadline),
              let reply = MCPToolReply.read(data) else { return .unanswered }
        return .reply(reply)
    }
}
#endif
