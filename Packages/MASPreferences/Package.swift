// swift-tools-version:5.9
import PackageDescription

// Vendored MASPreferences 1.3 (2-clause BSD). See PROVENANCE.md. The public
// headers live in Sources/MASPreferences/include/MASPreferences/ so consumers
// keep importing them as <MASPreferences/...>; the headerSearchPath lets the
// implementation's own quote-style includes (#import "MASPreferences...h")
// resolve.
let package = Package(
    name: "MASPreferences",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "MASPreferences", targets: ["MASPreferences"]),
    ],
    targets: [
        .target(
            name: "MASPreferences",
            cSettings: [
                .headerSearchPath("include/MASPreferences"),
            ]
        ),
    ]
)
