// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UltramarCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "UltramarCore", targets: ["UltramarCore"]),
    ],
    targets: [
        .target(name: "UltramarCore"),
        .testTarget(
            name: "UltramarCoreTests",
            dependencies: ["UltramarCore"]
        ),
    ]
)
