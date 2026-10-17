import Foundation
import XCTest
@testable import AgentHUDCore

/// Node.js for the tests that run a client plugin's script: `/usr/bin/env node` on macOS, as those tests always have;
/// on Windows the `node.exe` on `PATH`, the test skipping itself where there is none (docs/windows-port/SKIPPED_TESTS.md).
enum TestNode {
    /// What Node printed running `arguments`.
    static func run(_ arguments: [String]) async throws -> String {
        #if os(Windows)
        guard let node = Executables.first(Executables.onPath("node", path: Executables.systemPath)) else {
            throw XCTSkip("Node.js is not on PATH")
        }
        let output = try await ChildProcess.run(node, arguments, timeout: 60, stdoutLimit: 4 * 1024 * 1024)
        return String(decoding: output.stdout, as: UTF8.self) + String(decoding: output.stderr, as: UTF8.self)
        #else
        return try await ProviderCommand.run("/usr/bin/env", ["node"] + arguments)
        #endif
    }
}
