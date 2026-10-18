#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AgentHUDCore

/// The WinHTTP transport every quota request takes on Windows (`ProviderHTTP+Windows.swift`, D-014), against a loopback
/// host: the reply and the request as sent, and each rule it sends by — a redirect is the answer and is never followed,
/// no cookie is kept, no authentication is answered, the body limit, the timeout, and a request it cannot send safely is
/// not sent. No network and no credential: the token is a fixture. (The self-signed certificate rule for 127.0.0.1 needs
/// a TLS host and is not covered here.)
final class ProviderHTTPWindowsTests: XCTestCase, @unchecked Sendable {
    private func host(_ reply: @escaping @Sendable (LoopbackHTTPHost.Request) -> LoopbackHTTPHost.Reply) throws -> LoopbackHTTPHost {
        let host = try LoopbackHTTPHost(reply: reply)
        addTeardownBlock { host.stop() }
        return host
    }

    private func request(_ host: LoopbackHTTPHost, _ path: String = "/", timeout: TimeInterval = 10) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(host.port)\(path)")!)
        request.timeoutInterval = timeout
        return request
    }

    /// The error `ProviderHTTP.requestData` throws for `request`; fails when it succeeds.
    private func failure(_ request: URLRequest) async -> Error? {
        do {
            _ = try await ProviderHTTP.requestData(request)
            XCTFail("the request succeeded")
            return nil
        } catch {
            return error
        }
    }

    func testAReplyReturnsItsBodyAndTheRequestArrivesAsSent() async throws {
        let host = try host { _ in LoopbackHTTPHost.response(200, "OK", headers: ["Content-Type": "application/json"],
                                                              body: Data(#"{"used":42,"名":"额度"}"#.utf8)) }
        var request = request(host, "/v1/usage?account=a%20b&x=1")
        request.httpMethod = "POST"
        request.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"q":"用量"}"#.utf8)

        let data = try await ProviderHTTP.requestData(request)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"used":42,"名":"额度"}"#)
        let received = try XCTUnwrap(host.requests.first)
        XCTAssertEqual(received.line, "POST /v1/usage?account=a%20b&x=1 HTTP/1.1")
        XCTAssertEqual(received.header("Authorization"), "Bearer fixture-token")
        XCTAssertEqual(received.header("Content-Type"), "application/json")
        XCTAssertEqual(received.header("Host"), "127.0.0.1:\(host.port)")
        XCTAssertEqual(String(decoding: received.body, as: UTF8.self), #"{"q":"用量"}"#)
        XCTAssertEqual(host.connections, 1)
    }

    func testAnErrorStatusIsTheAnswer() async throws {
        let host = try host { _ in LoopbackHTTPHost.response(500, "Internal Server Error", body: Data("down".utf8)) }
        let error = await failure(request(host))
        XCTAssertEqual((error as? ProviderHTTPError)?.status, 500)
        XCTAssertEqual(try WindowsHTTP.send(request(host)).status, 500, "send itself hands back the status and the body")
    }

    /// A credential must never follow a redirect (D-014): the redirect is the answer, and the place it names is never
    /// asked.
    func testARedirectIsTheAnswerAndIsNeverFollowed() async throws {
        let elsewhere = try host { _ in LoopbackHTTPHost.response(200, "OK", body: Data("taken".utf8)) }
        for status in [301, 302, 307, 308] {
            let host = try host { _ in
                LoopbackHTTPHost.response(status, "Moved", headers: ["Location": "http://127.0.0.1:\(elsewhere.port)/steal"])
            }
            var request = request(host)
            request.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
            let error = await failure(request)
            XCTAssertEqual((error as? ProviderHTTPError)?.status, status)
            XCTAssertEqual(host.requests.count, 1, "\(status)")
        }
        XCTAssertEqual(elsewhere.connections, 0, "nothing went where the redirects pointed")
    }

    func testNoCookieIsKeptOrSent() async throws {
        let host = try host { _ in
            LoopbackHTTPHost.response(200, "OK", headers: ["Set-Cookie": "session=fixture; Path=/"], body: Data("{}".utf8))
        }
        _ = try await ProviderHTTP.requestData(request(host))
        _ = try await ProviderHTTP.requestData(request(host))
        XCTAssertEqual(host.requests.count, 2)
        XCTAssertNil(host.requests.last?.header("Cookie"))
    }

    /// WinHTTP answers no challenge itself (no default credentials, no Negotiate or NTLM logon): a 401 is the answer,
    /// and the host is asked once.
    func testAnAuthenticationChallengeIsTheAnswer() async throws {
        let host = try host { _ in
            LoopbackHTTPHost.response(401, "Unauthorized", headers: ["WWW-Authenticate": "Negotiate, NTLM, Basic realm=\"hud\""])
        }
        let error = await failure(request(host))
        XCTAssertEqual((error as? ProviderHTTPError)?.isAuthentication, true)
        XCTAssertEqual(host.requests.count, 1)
        XCTAssertNil(host.requests.first?.header("Authorization"))
    }

    func testABodyOverTheLimitFails() async throws {
        let body = Data(count: WindowsHTTP.bodyLimit + 1)
        let host = try host { _ in LoopbackHTTPHost.response(200, "OK", body: body) }
        let error = await failure(request(host, timeout: 30))
        XCTAssertEqual(error as? UsageProviderError, ProviderFailure.limit)
        let exact = try self.host { _ in LoopbackHTTPHost.response(200, "OK", body: Data(count: WindowsHTTP.bodyLimit)) }
        let data = try await ProviderHTTP.requestData(request(exact, timeout: 30))
        XCTAssertEqual(data.count, WindowsHTTP.bodyLimit, "a body of the limit itself is read whole")
    }

    func testAHostThatNeverAnswersTimesOut() async throws {
        let host = try host { _ in .silent }
        let started = Date()
        let error = await failure(request(host, timeout: 1))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual((error as? URLError)?.code, .timedOut, "\(String(describing: error))")
        XCTAssertLessThan(elapsed, 4, "the request's timeout, plus at most the watchdog's second")
        XCTAssertGreaterThanOrEqual(elapsed, 0.9)
    }

    func testARequestItCannotSendSafelyIsNotSent() async throws {
        let host = try host { _ in LoopbackHTTPHost.response(200, "OK") }
        for url in ["ftp://127.0.0.1:\(host.port)/", "file:///C:/Windows/win.ini", "http:///nohost"] {
            XCTAssertThrowsError(try WindowsHTTP.send(URLRequest(url: URL(string: url)!)), url) {
                XCTAssertEqual($0 as? UsageProviderError, ProviderFailure.format, url)
            }
        }
        // A header name with a line break would add a header of its choosing: the request is not sent.
        var named = request(host)
        named.setValue("1", forHTTPHeaderField: "X-Name\r\nX-Injected")
        XCTAssertThrowsError(try WindowsHTTP.send(named)) {
            XCTAssertEqual($0 as? UsageProviderError, ProviderFailure.local)
        }
        XCTAssertEqual(host.connections, 0, "nothing was sent")
        // swift-corelibs drops a value with a line break when it is set (measured: the request then has no such
        // header), so the guard never sees one; either way no injected header reaches the host.
        var valued = request(host)
        valued.setValue("Bearer fixture\r\nX-Injected: 1", forHTTPHeaderField: "Authorization")
        _ = try? WindowsHTTP.send(valued)
        XCTAssertFalse(host.requests.contains { $0.header("X-Injected") != nil }, "no header of the value's choosing")
    }

    func testAHostThatIsNotThereCannotBeReached() async throws {
        // A port the system just gave out and that nobody listens on any more.
        let gone = try LoopbackHTTPHost { _ in .silent }
        let port = gone.port
        gone.stop()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.timeoutInterval = 5
        let error = await failure(request)
        XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost, "\(String(describing: error))")
    }
}
#endif
