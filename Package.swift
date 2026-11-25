// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Syncer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // rsync routes: plan, preflight, diff, execute, hooks
        .library(
            name: "Syncer",
            targets: ["Syncer"]
        ),
        // the `Syncer` Frame module: routes from ~/.config/syncer/routes.frame
        .library(
            name: "SyncerFrame",
            targets: ["SyncerFrame"]
        ),
        // the `syncer` command
        .executable(
            name: "syncer",
            targets: ["SyncerCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-lco/Interfaces.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Difference.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Indentation.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Readers.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Errors.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/IO.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Path.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Partition.git", branch: "master"),
        .package(url: "https://github.com/lco-langs/Frame.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Terminal.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/ANSI.git", branch: "master"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Syncer",
            dependencies: [
                .product(name: "Interfaces", package: "Interfaces"),
                .product(name: "Difference", package: "Difference"),
                .product(name: "Indentation", package: "Indentation"),
                .product(name: "Readers", package: "Readers"),
                .product(name: "Errors", package: "Errors"),
            ]
        ),
        .target(
            name: "SyncerFrame",
            dependencies: [
                "Syncer",
                .product(name: "Errors", package: "Errors"),
                .product(name: "Frame", package: "Frame"),
                .product(name: "IO", package: "IO"),
                .product(name: "Path", package: "Path"),
                .product(name: "Partition", package: "Partition"),
                .product(name: "PartitionFrame", package: "Partition"),
                .product(name: "Readers", package: "Readers"),
            ]
        ),
        .executableTarget(
            name: "SyncerCLI",
            dependencies: [
                "Syncer",
                "SyncerFrame",
                .product(name: "Interfaces", package: "Interfaces"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Difference", package: "Difference"),
                .product(name: "Terminal", package: "Terminal"),
                .product(name: "ANSI", package: "ANSI"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
