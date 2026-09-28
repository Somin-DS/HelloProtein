// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MigrationCore",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [.library(name: "MigrationCore", targets: ["MigrationCore"])],
    dependencies: [.package(path: "../HelloProteinCore")],
    targets: [
        .target(name: "MigrationCore", dependencies: ["HelloProteinCore"]),
        .testTarget(name: "MigrationCoreTests", dependencies: ["MigrationCore", "HelloProteinCore"])
    ]
)
