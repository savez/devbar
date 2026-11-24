// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Devbar",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "DevbarCore", targets: ["DevbarCore"]),
        .executable(name: "Devbar", targets: ["Devbar"]),
    ],
    targets: [
        .target(name: "DevbarCore"),
        .executableTarget(name: "Devbar", dependencies: ["DevbarCore"]),
        .testTarget(
            name: "DevbarCoreTests",
            dependencies: ["DevbarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
