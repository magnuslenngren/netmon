// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetMon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NetMon",
            path: "Sources/NetMon",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
