// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SDVGCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SDVGCore", targets: ["SDVGCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "SDVGCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "SDVGCoreTests", dependencies: ["SDVGCore"]),
    ]
)
