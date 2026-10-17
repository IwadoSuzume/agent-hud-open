// swift-tools-version: 6.0
import PackageDescription

#if os(Windows)
// The community Windows port (docs/windows-port). Its targets join this branch milestone by milestone, as they build
// on Windows: Support first (M2), Core next (M3). AgentHUDDesktop and the macOS application are AppKit and SwiftUI,
// and are not built here.
let package = Package(
    name: "AgentHUDOpen",
    products: [
        .library(name: "AgentHUDSupport", targets: ["AgentHUDSupport"]),
    ],
    targets: [
        .target(name: "AgentHUDSupport", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AgentHUDSupportTests", dependencies: ["AgentHUDSupport"], resources: [.copy("Fixtures")]),
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
