// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "whisp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LewisWisper", targets: ["whisp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "whisp",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
