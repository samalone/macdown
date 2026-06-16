# JJPluralForm — vendored source

This package vendors [JJPluralForm](https://github.com/junjie/JJPluralForm),
an Objective-C plural-form helper adapted from Mozilla's `PluralForm`, so
MacDown can depend on it through SPM instead of `pod 'JJPluralForm', '~> 2.1'`.

- **Version:** 2.1
- **License:** MPL-2.0 (see `LICENSE`)
- **Source:** byte-for-byte the two source files (`JJPluralForm.h`,
  `JJPluralForm.m`) that previously shipped via the pod.

## Layout

Upstream ships a flat `JJPluralForm/` directory with the header and
implementation side by side. To expose the header as
`<JJPluralForm/JJPluralForm.h>` (matching MacDown's existing import in
`MPDocument.m`) while letting the implementation's quote-style
`#import "JJPluralForm.h"` resolve, the source is split:

- `Sources/JJPluralForm/JJPluralForm.m` — implementation
- `Sources/JJPluralForm/include/JJPluralForm/JJPluralForm.h` — public header
  (the SPM `publicHeadersPath` default, `include`, exposes it under the
  `JJPluralForm/` prefix)

`Package.swift` adds `include/JJPluralForm` to the C header search path so the
`#import "JJPluralForm.h"` in the implementation still resolves.

## How MacDown uses it

`-[MPDocument totalWordCount]` (and the character/line variants) pass a
localized, `;`-separated plural-form string and the localized
`JJ_PLURAL_FORM_RULE` index to `+pluralStringForNumber:withPluralForms:` to
build the word/character/line counts shown in the status display. The rule
index and the plural-form strings live in every `Localizable.strings` and
round-trip through Transifex, which is why JJPluralForm is **vendored, not
replaced** — swapping in a `.stringsdict` approach would churn translated
strings we are not allowed to hand-edit.

## Upstream status (researched 2026-06-16)

`junjie/JJPluralForm` is effectively dormant — `2.1` is the final tag and the
repository has seen no functional changes in years. The vendored source is the
pristine 2.1 release; there are no MacDown-local modifications.

## Updating

Replace the files under `Sources/JJPluralForm/` from a clean upstream checkout
(`.m` into the target root, `.h` into `include/JJPluralForm/`), keep `LICENSE`
current, and bump the version above.
