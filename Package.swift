// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetSpeed",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NetSpeed", targets: ["NetSpeed"])],
    targets: [
        .target(name: "NetSpeedCore"),
        .executableTarget(name: "NetSpeed", dependencies: ["NetSpeedCore"]),
        .testTarget(name: "NetSpeedCoreTests", dependencies: ["NetSpeedCore"])
    ]
)
