# GBCli — vendored source

This package vendors [GBCli](https://github.com/tomaz/GBCli), Tomaz Kragelj's
small Objective-C command-line parsing library, so MacDown can depend on it
through SPM instead of `pod 'GBCli', '~> 1.1'`.

- **Version:** 1.1
- **License:** MIT (see `LICENSE`)
- **Source:** byte-for-byte the `GBCli/src/` files that previously shipped via
  the pod — `GBCommandLineParser`, `GBSettings`, `GBOptionsHelper`, `GBPrint`,
  and the `GBCli.h` umbrella.

## Layout

Upstream ships a flat `GBCli/src/` directory with headers and implementations
side by side and an umbrella `GBCli.h` that quote-imports the four headers. To
expose the umbrella as `<GBCli/GBCli.h>` (matching MacDown's imports in
`main.m` and `MPArgumentProcessor.m`) while letting the quote-style includes
resolve, the source is split:

- `Sources/GBCli/*.m` — implementations
- `Sources/GBCli/include/GBCli/*.h` — public headers, including the `GBCli.h`
  umbrella (the SPM `publicHeadersPath` default, `include`, exposes them under
  the `GBCli/` prefix)

`Package.swift` adds `include/GBCli` to the C header search path so the
`#import "GBSettings.h"` style includes in both the umbrella and the
implementations still resolve.

## How MacDown uses it

Only the `macdown-cmd` target uses GBCli: `MPArgumentProcessor` builds a
`GBCommandLineParser` / `GBOptionsHelper` / `GBSettings` to parse the
`macdown` CLI helper's arguments. The main app target does not link GBCli.

## Upstream status (researched 2026-06-16)

`tomaz/GBCli` is dormant — `1.1` is the last release and the repository has
seen no functional changes in years. The vendored source is the pristine 1.1
release; there are no MacDown-local modifications.

## Updating

Replace the files under `Sources/GBCli/` from a clean upstream checkout
(`.m` into the target root, `.h` into `include/GBCli/`), keep `LICENSE`
current, and bump the version above.
