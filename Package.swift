// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NetBar", targets: ["NetBar"])],
    targets: [
        .target(name: "NetBarCore"),
        .executableTarget(name: "NetBar", dependencies: ["NetBarCore"]),
        .testTarget(name: "NetBarCoreTests", dependencies: ["NetBarCore"])
    ]
)
