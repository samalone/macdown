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

## Upstream status & fork history (researched 2026-06-15)

Lineage (see `LICENSE`): **Upskirt** (Natacha Porté, 2008) → **Sundown**
(Vicent Martí / GitHub, 2011) → **Hoedown** (Xavier Mendez, Devin Torres et
al., 2014). Each link was a revival of the previous one after it was
abandoned; hoedown itself was created to revive Sundown after GitHub
deprecated it.

**Upstream `hoedown/hoedown` is de facto abandoned.** Last real commit
2015-12-07 (PR #187); `3.0.7` is the final tag (no GitHub Releases, only
tags); not formally archived but sitting on ~61 open issues / ~11 open PRs
untouched for a decade. Upstream `master` is 4 commits ahead of the `3.0.7`
tag — two small *unreleased* parser fixes from Dec 2015 (saner image parsing;
a `char_escape` backslash-passthrough edge case) we could absorb if wanted.
The maintained successors in the ecosystem are CommonMark's `cmark` and
`md4c`; migrating to either is a renderer rewrite, out of scope here.

**The old `MacDownApp/hoedown` fork was not a source fork.** Its `master` is
byte-identical to upstream `master` (ahead 0 / behind 0); the fork plus the
patched `MacDownApp/cocoapods-specs` podspec existed only to control
packaging, not to change hoedown's code. MacDown's actual behavior changes
(GitHub task lists, code-block line numbers, the code-block info /
`language_addition` callback, custom TOC headers) live in the app's
`MacDown/Code/Extension/hoedown_html_patch.c`, layered on hoedown's
renderer-state extension mechanism — which is why the vendored source here is
pristine upstream 3.0.7. Keep that patch with the renderer, not in this
package.

## Updating

Replace the files under `Sources/hoedown/` from a clean upstream 3.0.x
checkout (`.c` into the target root, `.h` into `include/hoedown/`), keep
`LICENSE` current, and bump the version above.
