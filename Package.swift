// swift-tools-version: 6.1

import CompilerPluginSupport
import PackageDescription
import Foundation

let artifactPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GRDBArtifact.lock.json")
let artifact = try! JSONSerialization.jsonObject(with: Data(contentsOf: artifactPath)) as! [String: Any]
let grdbURL = artifact["url"] as! String
let grdbChecksum = artifact["checksum"] as! String

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
