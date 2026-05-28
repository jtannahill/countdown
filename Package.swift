// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Countdown",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Countdown", path: "Sources/Countdown"),
        .testTarget(
            name: "CountdownTests",
            dependencies: ["Countdown"],
            path: "Tests/CountdownTests"
        ),
    ]
)
