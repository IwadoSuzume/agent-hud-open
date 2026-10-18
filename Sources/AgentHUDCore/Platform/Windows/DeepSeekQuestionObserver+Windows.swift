#if os(Windows)
import Foundation

extension DeepSeekQuestionObserver {
    /// `stream(port:onFrame:shouldStop:)` on Windows: the same downlink WebSocket, over WinHTTP (`WindowsWebSocket`,
    /// D-040). The connection ends when the socket does or the task is cancelled; the caller reconnects through
    /// `connect` again, as on macOS.
    static func windowsStream(port: Int, onFrame: @escaping @Sendable (ProviderJSON) -> Void,
                              shouldStop: @escaping @MainActor @Sendable () -> Bool) async {
        guard !Task.isCancelled, !shouldStop() else { return }
        let socket = WindowsWebSocket(port: port, path: "/api/events.mux", timeout: 5)
        defer { socket.cancel() }
        await withTaskCancellationHandler {
            for await message in socket.messages {
                guard !Task.isCancelled, !shouldStop() else { return }
                switch message {
                case .data(let data): if let frame = try? ProviderJSON.read(data) { onFrame(frame) }
                case .string(let text): if let frame = try? ProviderJSON.read(Data(text.utf8)) { onFrame(frame) }
                }
            }
        } onCancel: {
            socket.cancel()
        }
    }
}
#endif
