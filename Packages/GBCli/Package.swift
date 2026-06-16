// swift-tools-version:5.9
import PackageDescription

// Vendored GBCli 1.1 (MIT). See PROVENANCE.md. The public headers live in
// Sources/GBCli/include/GBCli/ so consumers keep importing the umbrella as
// <GBCli/GBCli.h>; the headerSearchPath lets the implementation's own
// quote-style includes (#import "GBSettings.h") resolve.
let package = Package(
    name: "GBCli",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "GBCli", targets: ["GBCli"]),
    ],
    targets: [
        .target(
            name: "GBCli",
            cSettings: [
                .headerSearchPath("include/GBCli"),
            ]
        ),
    ]
)
