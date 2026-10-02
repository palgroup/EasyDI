// swift-tools-version: 6.3
// The numbers in the README: `swift run -c release` in this folder.

import PackageDescription

let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "EasyDI", path: "..")],
    targets: [
        .executableTarget(
            name: "Benchmarks",
            dependencies: [.product(name: "EasyDI", package: "EasyDI")]
        ),
    ]
)
