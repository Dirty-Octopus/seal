// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Seal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Seal", targets: ["Seal"])
    ],
    targets: [
        .executableTarget(
            name: "Seal",
            path: "Sources/Seal"
        )
    ]
)
