// swift-tools-version:5.9
import PackageDescription

// Vendored hoedown 3.0.7 (ISC). See PROVENANCE.md. The public headers live in
// Sources/hoedown/include/hoedown/ so consumers keep importing them as
// <hoedown/html.h>; the headerSearchPath lets hoedown's own quote-style
// includes (#include "buffer.h") and the .c files resolve those same headers.
let package = Package(
    name: "Hoedown",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Hoedown", targets: ["hoedown"]),
    ],
    targets: [
        .target(
            name: "hoedown",
            cSettings: [
                .headerSearchPath("include/hoedown"),
            ]
        ),
    ]
)
