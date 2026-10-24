// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GridFleetCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "GridFleetCore", targets: ["GridFleetCore"]),
    ],
    targets: [
        .target(name: "GridFleetCore"),
        .testTarget(name: "GridFleetCoreTests", dependencies: ["GridFleetCore"]),
    ]
)
