// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndroidFileManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AndroidFileManager", targets: ["AndroidFileManager"]),
    ],
    targets: [
        .executableTarget(
            name: "AndroidFileManager",
            path: "Sources",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "AndroidFileManagerTests",
            dependencies: ["AndroidFileManager"],
            path: "Tests"
        ),
    ]
)
