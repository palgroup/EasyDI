// swift-tools-version: 6.3
// 6.3 is the first Swift with `@section` and `@used` (SE-0492), which the
// macros use to register providers without a central list.

import CompilerPluginSupport
import PackageDescription

/// The upcoming features Swift 7 turns on by default: the package builds clean with them.
let swift7: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]

let package = Package(
    name: "EasyDI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EasyDI", targets: ["EasyDI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.0"..<"605.0.0"),
    ],
    targets: [
        .macro(
            name: "EasyDIMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: swift7
        ),
        .target(name: "EasyDI", dependencies: ["EasyDIMacros"], swiftSettings: swift7),
        .testTarget(
            name: "EasyDITests",
            dependencies: ["EasyDI"],
            // Like an app target: code is on the main actor unless it says otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)] + swift7
        ),
        .testTarget(
            name: "EasyDIMacrosTests",
            dependencies: [
                "EasyDIMacros",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: swift7
        ),
    ]
)
