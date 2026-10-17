// swift-tools-version: 6.0
import PackageDescription

#if os(Windows)
/// Core files whose macOS implementation the Windows build replaces with one of the same API in
/// Sources/AgentHUDCore/Platform/Windows; the macOS files themselves are left untouched (docs/windows-port D-006).
let windowsReplaced = [
    "System/UnixSocket.swift",
    "System/UnixSocketListener.swift",
    "System/ChildProcess.swift",
    "System/FileChangeMonitor.swift",
    "System/InstanceLock.swift",
    "Providers/Codex/CodexDesktopIPC.swift",
]

/// Core test files that do not build on Windows: each is listed with its reason and its Windows counterpart in
/// docs/windows-port/SKIPPED_TESTS.md.
let windowsSkippedTests = [
    "System/UnixSocketListenerTests.swift",
    "System/ChildProcessTests.swift",
    "System/InstanceLockTests.swift",
    "MCP/MCPAppChannelTests.swift",
    "Hooks/Permission/PermissionHookTests.swift",
    "Hooks/Permission/DeepSeekQuestionObserverTests.swift",
    "Providers/Codex/CodexDaemonOriginTransportTests.swift",
    "Providers/Codex/CodexDesktopTestServer.swift",
    "Providers/Codex/CodexDesktopPermissionsTests.swift",
    "Providers/Codex/CodexDesktopStreamTests.swift",
]

// The community Windows port (docs/windows-port): Support and Core, over the system's winsqlite3 and WinHTTP.
// AgentHUDDesktop and the macOS application are AppKit and SwiftUI, and are not built here.
let package = Package(
    name: "AgentHUDOpen",
    products: [
        .library(name: "AgentHUDSupport", targets: ["AgentHUDSupport"]),
        .library(name: "AgentHUDCore", targets: ["AgentHUDCore"]),
    ],
    targets: [
        .systemLibrary(name: "SQLite3", path: "Sources/SQLite3Windows"),
        .systemLibrary(name: "CWinHTTP", path: "Sources/CWinHTTP"),
        .target(name: "AgentHUDSupport", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AgentHUDCore", dependencies: ["AgentHUDSupport", "SQLite3", "CWinHTTP"], exclude: windowsReplaced,
                swiftSettings: [.swiftLanguageMode(.v6)], linkerSettings: [.linkedLibrary("ntdll")]),
        .testTarget(name: "AgentHUDSupportTests", dependencies: ["AgentHUDSupport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "AgentHUDCoreTests", dependencies: ["AgentHUDCore", "AgentHUDSupport", "SQLite3"],
                    exclude: windowsSkippedTests, resources: [.copy("Providers/Kit/Zstandard/Fixtures")]),
    ]
)
#else
let package = Package(
    name: "AgentHUDOpen",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentHUDSupport", targets: ["AgentHUDSupport"]),
        .library(name: "AgentHUDCore", targets: ["AgentHUDCore"]),
        .library(name: "AgentHUDDesktop", targets: ["AgentHUDDesktop"]),
        .executable(name: "AgentHUDOpen", targets: ["AgentHUDOpenApp"]),
    ],
    targets: [
        .target(name: "AgentHUDSupport", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AgentHUDCore", dependencies: ["AgentHUDSupport"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AgentHUDDesktop", dependencies: ["AgentHUDCore"], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "AgentHUDOpenApp", dependencies: ["AgentHUDDesktop", "AgentHUDCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AgentHUDSupportTests", dependencies: ["AgentHUDSupport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "AgentHUDCoreTests", dependencies: ["AgentHUDCore", "AgentHUDSupport"],
                    resources: [.copy("Providers/Kit/Zstandard/Fixtures")]),
        .testTarget(name: "AgentHUDDesktopTests", dependencies: ["AgentHUDDesktop"]),
    ]
)
#endif
