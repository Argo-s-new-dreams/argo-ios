// swift-tools-version: 5.10
// Calcola le impronte vocali con FluidAudio (lo stesso motore di Argo per iPhone), su macOS.
import PackageDescription

let package = Package(
    name: "impronta-fluid",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .executableTarget(
            name: "impronta-fluid",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
