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
    ],
    dependencies: [
        .package(url: "https://github.com/swift-lco/Interfaces.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Difference.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Indentation.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Readers.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Errors.git", branch: "master"),
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
    ],
    swiftLanguageModes: [.v6]
)
