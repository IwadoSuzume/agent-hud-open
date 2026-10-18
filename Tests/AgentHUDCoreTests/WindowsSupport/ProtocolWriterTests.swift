#if os(Windows)
import Foundation
import XCTest
@testable import AgentHUDCore

/// The engine's output queue (`EngineServe.ProtocolWriter.enqueue`, PROTOCOL.md "The exchange" 3) and the memo of
/// session projects (`ShellProtocol.projectTitle`): the rules a stalled shell and a busy report rely on.
final class ProtocolWriterTests: XCTestCase, @unchecked Sendable {
    private typealias Writer = EngineServe.ProtocolWriter

    private func queue(_ lines: [(String, String)]) -> [Writer.Queued] {
        var queue: [Writer.Queued] = []
        for (kind, text) in lines { Writer.enqueue(Data(text.utf8), kind: kind, into: &queue) }
        return queue
    }

    private func texts(_ queue: [Writer.Queued]) -> [String] { queue.map { String(decoding: $0.line, as: UTF8.self) } }

    func testANewerHelloTakesTheQueuedOnesPlaceSoAHelloStillComesFirst() {
        let queued = queue([("hello", "hello en"), ("state", "state 1"), ("hello", "hello zh")])
        XCTAssertEqual(texts(queued), ["hello zh", "state 1"], "the shell never reads a state before a hello")
    }

    func testANewerStateGoesToTheEndAfterTheLinesBeforeIt() {
        let queued = queue([("state", "state 1"), ("event", "event a"), ("hello", "hello zh"), ("state", "state 2")])
        XCTAssertEqual(texts(queued), ["event a", "hello zh", "state 2"])
    }

    func testOtherLinesKeepTheirOrderAndAreNeverReplaced() {
        let queued = queue([("event", "a"), ("error", "b"), ("event", "c"), ("lock-held", "d")])
        XCTAssertEqual(texts(queued), ["a", "b", "c", "d"])
    }

    func testAPileUpDropsErrorsFirstThenTheOldestEventNeverTheHelloOrTheState() {
        var lines: [(String, String)] = [("hello", "hello"), ("state", "state"), ("error", "error 1")]
        lines += (1...(Writer.limit - 3)).map { ("event", "event \($0)") }
        var queued = queue(lines)
        XCTAssertEqual(queued.count, Writer.limit)
        Writer.enqueue(Data("event new".utf8), kind: "event", into: &queued)
        XCTAssertEqual(queued.count, Writer.limit)
        XCTAssertFalse(texts(queued).contains("error 1"), "an error goes first")
        XCTAssertTrue(texts(queued).contains("event 1"))
        Writer.enqueue(Data("event newer".utf8), kind: "event", into: &queued)
        XCTAssertEqual(queued.count, Writer.limit)
        XCTAssertFalse(texts(queued).contains("event 1"), "then the oldest event")
        XCTAssertEqual(Array(texts(queued).prefix(2)), ["hello", "state"], "never the hello or the state")
        XCTAssertEqual(texts(queued).last, "event newer")
    }

    /// One walk of the folders per working directory and report: a repository that appears meanwhile is seen with the
    /// next report, not with the next state of the same one.
    @MainActor
    func testAProjectIsWalkedOncePerReport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 项目 \(UUID().uuidString)")
        let repository = root.appendingPathComponent("repository"), folder = repository.appendingPathComponent("sub folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let session = LiveSession(id: "s", agentId: "claude", task: "t", terminal: nil, startedAt: Date(), pctOfWindow: nil,
                                  tokensIn: 0, tokensOut: 0, workingDirectory: folder.path)
        let first = Date(timeIntervalSince1970: 1_000), second = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(ShellProtocol.projectTitle(session, report: first), "sub folder")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        XCTAssertEqual(SessionProject(session).title, "repository", "the folder is now in a repository")
        XCTAssertEqual(ShellProtocol.projectTitle(session, report: first), "sub folder", "the same report is not walked again")
        XCTAssertEqual(ShellProtocol.projectTitle(session, report: second), "repository", "a new report is")
        let outside = LiveSession(id: "o", agentId: "claude", task: "t", terminal: nil, startedAt: Date(), pctOfWindow: nil,
                                  tokensIn: 0, tokensOut: 0, workingDirectory: nil)
        XCTAssertNil(ShellProtocol.projectTitle(outside, report: second), "no folder, no project")
        XCTAssertNil(ShellProtocol.projectTitle(outside, report: second), "a remembered nil stays nil")
    }
}
#endif
