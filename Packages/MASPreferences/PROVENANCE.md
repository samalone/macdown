# MASPreferences — vendored source

This package vendors [MASPreferences](https://github.com/shpakovski/MASPreferences),
Vadim Shpakovski's tabbed preferences-window controller for AppKit, so MacDown
can depend on it through SPM instead of `pod 'MASPreferences', '~> 1.3'`.

- **Version:** 1.3
- **License:** 2-clause BSD (see `LICENSE`)
- **Source:** byte-for-byte the `Framework/` files that previously shipped via
  the pod — `MASPreferencesWindowController` (the `NSWindowController`),
  `MASPreferencesViewController` (the protocol each pane adopts), and the
  `MASPreferences.h` umbrella. AppKit-only; no other dependencies.

## Layout

Upstream ships a flat `Framework/` directory with the header and implementation
side by side. To expose the headers as `<MASPreferences/...>` (matching
MacDown's imports in `MPMainController` and the six preference panes) while
letting the implementation's quote-style includes resolve, the source is split:

- `Sources/MASPreferences/MASPreferencesWindowController.m` — implementation
- `Sources/MASPreferences/include/MASPreferences/*.h` — public headers (the SPM
  `publicHeadersPath` default, `include`, exposes them under the
  `MASPreferences/` prefix)

`Package.swift` adds `include/MASPreferences` to the C header search path so the
`#import "MASPreferencesWindowController.h"` style includes in the umbrella and
the implementation still resolve.

## The window nib (`Resources/MASPreferencesWindow.xib`)

Upstream also ships a nib (declared as a CocoaPods `resources:` entry). The
window controller loads it with
`[NSBundle bundleForClass:MASPreferencesWindowController.class]
pathForResource:@"MASPreferencesWindow" ofType:@"nib"]`. Because the package is
statically linked into the app, `bundleForClass:` resolves to the **main app
bundle**, so the nib must live there — an SPM resource bundle
(`Bundle.module`) would not be found without patching the (pristine) source.

The nib therefore lives in `Resources/MASPreferencesWindow.xib` (outside the
SwiftPM `Sources/` tree, so SwiftPM ignores it) and is added directly to the
**MacDown app target's** Copy Bundle Resources, which compiles it into
`MASPreferencesWindow.nib` in the app bundle — exactly where the pod's resource
landed before.

## How MacDown uses it

`MPMainController` builds a single `MASPreferencesWindowController` via
`-initWithViewControllers:title:` from the six preference panes (General,
Editor, Markdown, HTML, Print, Terminal), each of which adopts the
`MASPreferencesViewController` protocol. MacDown does not use the optional
navigation API (`goNextTab:`/`goPreviousTab:`, `selectControllerWith…`, the
did-change-view notification).

## Upstream status (researched 2026-06-16)

`shpakovski/MASPreferences` is largely dormant — `1.3` is the last tagged
release and the repository has seen little activity in years. The vendored
source is the pristine 1.3 release; there are no MacDown-local modifications.

A native replacement (an `NSTabViewController` with `.toolbar` tab style is the
modern AppKit idiom for this kind of window) is a possible future modernization
and would remove this package entirely.

## Updating

Replace the files under `Sources/MASPreferences/` from a clean upstream checkout
(`.m` into the target root, `.h` into `include/MASPreferences/`), keep `LICENSE`
current, and bump the version above.
