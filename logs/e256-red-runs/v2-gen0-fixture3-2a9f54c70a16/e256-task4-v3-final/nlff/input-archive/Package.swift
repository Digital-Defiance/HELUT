// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "helut",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HELUTCore", targets: ["HELUTCore"]),
        .library(name: "HELUTCLI", targets: ["HELUTCLI"]),
        .library(name: "HELUTToolKit", targets: ["HELUTToolKit"]),
        /// C ABI for GNU Radio / ctypes (`include/helut.h` → `libHELUTRadio.dylib`).
        .library(name: "HELUTRadio", type: .dynamic, targets: ["HELUTRadio"]),
        .executable(name: "helut", targets: ["helut"]),
        .executable(name: "helut-bench", targets: ["helut-bench"]),
        .executable(name: "helut-e256", targets: ["helut-e256"]),
        .executable(name: "helut-bombe", targets: ["helut-bombe"]),
        .executable(name: "helut-compile", targets: ["helut-compile"]),
        .executable(name: "helut-radio", targets: ["helut-radio"]),
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
        .target(
            name: "HELUTCLI",
            dependencies: ["HELUTCore"]
        ),
        .target(
            name: "HELUTToolKit",
            dependencies: ["HELUTCore", "HELUTCLI"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShadersGraph"),
                .linkedFramework("Network")
            ]
        ),
        .target(
            name: "HELUTRadio",
            dependencies: ["HELUTCore"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShadersGraph"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "helut",
            dependencies: ["HELUTToolKit", "HELUTCLI"]
        ),
        .executableTarget(
            name: "helut-bench",
            dependencies: ["HELUTToolKit", "HELUTCLI"]
        ),
        .executableTarget(
            name: "helut-e256",
            dependencies: ["HELUTToolKit", "HELUTCLI"]
        ),
        .executableTarget(
            name: "helut-bombe",
            dependencies: ["HELUTToolKit", "HELUTCLI"]
        ),
        .executableTarget(
            name: "helut-compile",
            dependencies: ["HELUTToolKit", "HELUTCLI"]
        ),
        .executableTarget(
            name: "helut-radio",
            dependencies: ["HELUTRadio"]
        ),
        .testTarget(
            name: "HELUTTests",
            dependencies: ["HELUTCore", "HELUTToolKit"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShadersGraph"),
                .linkedFramework("Network")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
