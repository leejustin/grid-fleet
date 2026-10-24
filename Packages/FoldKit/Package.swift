// swift-tools-version: 6.0
import PackageDescription

// FoldKit is the fold-posture helper shared by Carriage, Grid Fleet and Firstlight.
// It has no app-specific code so it can move to its own repo unchanged.
let package = Package(
    name: "FoldKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "FoldKit", targets: ["FoldKit"]),
    ],
    targets: [
        .target(name: "FoldKit"),
        .testTarget(name: "FoldKitTests", dependencies: ["FoldKit"]),
    ]
)
