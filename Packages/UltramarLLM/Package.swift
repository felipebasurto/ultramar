// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UltramarLLM",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "UltramarLLM", targets: ["UltramarLLM"]),
    ],
    dependencies: [
        .package(path: "../UltramarCore"),
        .package(url: "https://github.com/mattt/llama.swift", exact: "2.9279.0"),
    ],
    targets: [
        .target(
            name: "UltramarLLM",
            dependencies: [
                "UltramarCore",
                .product(name: "LlamaSwift", package: "llama.swift"),
            ]
        ),
        .testTarget(
            name: "UltramarLLMTests",
            dependencies: ["UltramarLLM"]
        ),
    ]
)
