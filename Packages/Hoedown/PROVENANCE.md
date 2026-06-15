# hoedown — vendored source

This package vendors the [hoedown](https://github.com/hoedown/hoedown) C
Markdown engine so MacDown can depend on it through SPM instead of the patched
`MacDownApp/cocoapods-specs` CocoaPods spec.

- **Version:** 3.0.7
- **License:** ISC (see `LICENSE`)
- **Source:** the `hoedown/standard` subspec, byte-for-byte the 3.0.7 source
  that previously shipped via `pod 'hoedown', '~> 3.0.7'`.

## Layout

Upstream ships a flat `src/` directory. To expose the headers as
`<hoedown/...>` (matching MacDown's existing imports) while letting hoedown's
internal quote-style includes resolve, the source is split:

- `Sources/hoedown/*.c` — implementation
- `Sources/hoedown/include/hoedown/*.h` — public headers (the SPM
  `publicHeadersPath` default, `include`, exposes them under the `hoedown/`
  prefix)

`Package.swift` adds `include/hoedown` to the C header search path so the
`#include "buffer.h"` style includes in the upstream sources still resolve.

## Not vendored here

MacDown's local hoedown extension (`hoedown_html_patch.c`) is **not** part of
this package — it stays with its renderer code in the app target and imports
these headers as `<hoedown/...>`.

## Updating

Replace the files under `Sources/hoedown/` from a clean upstream 3.0.x
checkout (`.c` into the target root, `.h` into `include/hoedown/`), keep
`LICENSE` current, and bump the version above.
