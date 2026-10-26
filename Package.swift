// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Obeshchal",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Obeshchal", targets: ["ObeshchalApp"])],
    targets: [
        .target(name: "ObeshchalCore"),
        .executableTarget(name: "ObeshchalApp", dependencies: ["ObeshchalCore"]),
        .testTarget(name: "ObeshchalCoreTests", dependencies: ["ObeshchalCore"])
    ],
    swiftLanguageModes: [.v5]
)
