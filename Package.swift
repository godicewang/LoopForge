// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoopForge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LoopForge", targets: ["LoopForge"])
    ],
    targets: [
        .executableTarget(
            name: "LoopForge",
            path: "Sources/LoopForge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LoopForgeTests",
            dependencies: ["LoopForge"],
            path: "Tests/LoopForgeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
