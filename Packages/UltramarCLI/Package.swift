// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UltramarCLI",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ultramar", targets: ["ultramar"]),
    ],
    dependencies: [
        .package(path: "../UltramarCore"),
        .package(path: "../UltramarLLM"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ultramar",
            dependencies: [
                "UltramarCore",
                "UltramarLLM",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ultramar"
        ),
        .testTarget(
            name: "UltramarCLITests",
            dependencies: [
                "ultramar",
                "UltramarLLM",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tests/UltramarCLITests"
        ),
    ]
)
