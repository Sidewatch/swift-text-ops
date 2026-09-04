// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TextOps",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TextOps", targets: ["TextOps"]),
    ],
    targets: [
        .target(name: "TextOps", path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "TextOpsTests", dependencies: ["TextOps"], path: "Tests"),
    ]
)
