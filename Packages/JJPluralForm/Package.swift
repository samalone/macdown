// swift-tools-version:5.9
import PackageDescription

// Vendored JJPluralForm 2.1 (MPL-2.0). See PROVENANCE.md. The public header
// lives in Sources/JJPluralForm/include/JJPluralForm/ so consumers keep
// importing it as <JJPluralForm/JJPluralForm.h>; the headerSearchPath lets the
// implementation's own quote-style include (#import "JJPluralForm.h") resolve.
let package = Package(
    name: "JJPluralForm",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "JJPluralForm", targets: ["JJPluralForm"]),
    ],
    targets: [
        .target(
            name: "JJPluralForm",
            cSettings: [
                .headerSearchPath("include/JJPluralForm"),
            ]
        ),
    ]
)
