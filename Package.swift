// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "helut",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HELUTCore", targets: ["HELUTCore"]),
        .executable(name: "helut", targets: ["helut"])
    ],
    targets: [
        .target(
            name: "HELUTCore",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShadersGraph"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "helut",
            dependencies: ["HELUTCore"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShadersGraph"),
                .linkedFramework("Network")
            ]
        ),
        .testTarget(
            name: "HELUTTests",
            dependencies: ["HELUTCore"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShadersGraph"),
                .linkedFramework("Network")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
