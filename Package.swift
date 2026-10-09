// swift-tools-version: 6.1

import CompilerPluginSupport
import PackageDescription
let grdbURL = "https://github.com/FeliksLv01/ORMKit/releases/download/grdb-7.11.1-2a580b4daed3e2bf22054aa022168239812ce82ca389b37374823b44e6902a5f/GRDB.xcframework.zip"
let grdbChecksum = "80fa7241597b5de746ea9a275637824defdb645399c23799db6132c58ccf4921"

let package = Package(
    name: "ORMKit",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v9)],
    products: [
        .library(name: "ORMKit", targets: ["ORMKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "603.0.0"),
    ],
    targets: [
        .binaryTarget(name: "GRDB", url: grdbURL, checksum: grdbChecksum),
        .macro(
            name: "ORMKitMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "ORMKit",
            dependencies: [
                "ORMKitMacros",
                "GRDB",
            ]
        ),
        .testTarget(
            name: "ORMKitMacrosTests",
            dependencies: [
                "ORMKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "ORMKitTests",
            dependencies: ["ORMKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
