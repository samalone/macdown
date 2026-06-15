// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacDownKit",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "MacDownKit", targets: ["MacDownKit"]),
    ],
    targets: [
        .target(name: "MacDownKit"),
    ]
)
