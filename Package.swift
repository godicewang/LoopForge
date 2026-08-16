// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoopForge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LoopForge", targets: ["LoopForge"]),
        .executable(name: "KernelSandboxGate", targets: ["KernelSandboxGate"]),
        .executable(
            name: "LoopForgeProviderHarness",
            targets: ["LoopForgeProviderHarness"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LoopForge",
            path: "Sources/LoopForge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "KernelProcessFixture",
            path: "Tests/KernelProcessFixture",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "KernelSandboxGate",
            path: "Sources/KernelSandboxGate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "LoopForgeProviderHarness",
            path: "Sources/LoopForgeProviderHarness",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LoopForgeTests",
            dependencies: [
                "LoopForge",
                "KernelProcessFixture",
                "KernelSandboxGate",
                "LoopForgeProviderHarness"
            ],
            path: "Tests/LoopForgeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
