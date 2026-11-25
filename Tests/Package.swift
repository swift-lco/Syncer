// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SyncerTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "t_syncer",
            targets: ["SyncerTestFlows"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-tooling/TestFlows.git", branch: "master"),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "SyncerTestFlows",
            dependencies: [
                .product(name: "Syncer", package: "Syncer"),
                .product(name: "TestFlows", package: "TestFlows"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
