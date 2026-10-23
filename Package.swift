// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NetBar", targets: ["NetBar"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "NetBarCore"),
        .executableTarget(name: "NetBar", dependencies: ["NetBarCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "NetBarCoreTests", dependencies: ["NetBarCore"])
    ]
)
