// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "HelloProteinCore",
    platforms: [.iOS(.v15), .macOS(.v10_15)],
    products: [.library(name: "HelloProteinCore", targets: ["HelloProteinCore"])],
    targets: [
        .target(name: "HelloProteinCore"),
        .testTarget(name: "HelloProteinCoreTests", dependencies: ["HelloProteinCore"])
    ]
)
