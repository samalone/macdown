# MacDown

An open-source Markdown editor for macOS, written in **Objective-C** (Cocoa/AppKit).
Live side-by-side editing with a synchronized HTML preview. Released under the MIT
License. This is a fork of [MacDownApp/macdown](https://github.com/MacDownApp/macdown),
which has been dormant since 2021 — see "Revival notes" below.

## Build & setup

**CocoaPods has been fully retired** (June 2026, completing epic `macdown-8tk.7`).
Every dependency is now a Swift Package — local packages under `Packages/` (Hoedown,
JJPluralForm, GBCli, MASPreferences, MacDownKit) or remote (swift-yaml,
swift-collections, and **Sparkle 2** for auto-update). There is no Podfile, no
`Pods/`, no Gemfile, and **no `MacDown.xcworkspace`**. First-time setup from the repo
root:

```bash
git submodule update --init                       # fetches Dependency/prism
make -C Dependency/peg-markdown-highlight          # builds the PEG highlighter (C)
```

Then open **`MacDown.xcodeproj`** in Xcode (the workspace is gone). Xcode resolves the
Swift Packages on first open from the committed `Package.resolved`
(`MacDown.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).

- `pmh_parser.c` (from `Dependency/peg-markdown-highlight`) is generated and
  gitignored, so the `make` step must run before the first build.
- If package resolution misbehaves, let Xcode re-resolve (File ▸ Packages ▸ Resolve)
  or delete DerivedData; do not hand-edit `Package.resolved`.

### Build / test from the command line

```bash
xcodebuild -project MacDown.xcodeproj -scheme MacDown build
xcodebuild -project MacDown.xcodeproj -scheme MacDown test
```

The only shared scheme is **MacDown**. There are three targets:

- **MacDown** — the app.
- **MacDownTests** — XCTest unit tests (`MacDownTests/MP*Tests.m`).
- **macdown-cmd** — the `macdown` command-line helper (`macdown-cmd/`), which opens
  files in the app from the terminal.

## Architecture

Objective-C with ARC (`CLANG_ENABLE_OBJC_ARC = YES`). All app classes use the **`MP`**
prefix. Source lives under `MacDown/Code/`, grouped by role:

- **`Application/`** — app-level controllers. `MPMainController` is the
  `NSApplicationDelegate`; `MPToolbarController`, `MPPlugInController`, and the export
  panel accessory live here.
- **`Document/`** — the core. `MPDocument` (`NSDocument` subclass, ~2000 lines) owns
  one editor window and drives everything. `MPRenderer` turns Markdown → HTML.
  `MPAsset` models CSS/JS assets injected into the preview.
- **`Preferences/`** — `MPPreferences` (a `PAPreferences` singleton wrapping
  `NSUserDefaults`) plus one `MASPreferences` pane controller per tab (General,
  Editor, Markdown, HTML, Terminal).
- **`View/`** — `MPEditorView` (the `NSTextView`) and `MPDocumentSplitView`.
- **`Extension/`** — categories on Cocoa/WebKit classes and the
  `hoedown_html_patch.c` C patch to the renderer.
- **`Utility/`** — globals, plug-in support, MathJax bridge, Homebrew subprocess
  helper.

### Rendering pipeline (the heart of the app)

Markdown is rendered to HTML in `MPRenderer` using the **Hoedown** C library
(`#import <hoedown/...>`), with a local patch in `Extension/hoedown_html_patch.c`.
The HTML is displayed in a legacy **`WebView`** (WebKit's deprecated `WebView`, not
`WKWebView`). Supporting pieces:

- **Prism** (`Dependency/prism` submodule, bundled into `Resources/Prism/`) — syntax
  highlighting inside code blocks, loaded per-language.
- **MathJax** (`Resources/MathJax/`, v2.7.x) — LaTeX math. See the comment block in
  `MPRenderer.m` about MathJax issue #548 and the `WebResourceLoadDelegate`.
- **peg-markdown-highlight** (`Dependency/peg-markdown-highlight`, built via `make`) —
  highlights Markdown *in the editor* (the `NSTextView`), separate from preview
  rendering.

Editor styling (Themes), preview CSS (Styles), HTML templates, and the
`syntax_highlighting.json` map all live in `MacDown/Resources/`.

## Versioning

- The human version lives in **`Tools/version.txt`** (currently `0.8.0`), NOT in the
  Info.plist (which holds a placeholder `0.1`).
- `Dependency/version` runs `Tools/generate_version_header.sh` at build time to emit a
  `version.h` consumed by the app. Bundle/build numbers come from
  `Tools/update_build_number.sh` (git-based).
- Release packaging is automated by `Tools/build_for_release.py`.

## Conventions

`CONTRIBUTING.md` is the source of truth; the important rules:

- **80-column limit** on all lines (except long URLs in comments).
- **Allman brace style** — braces on their own line.
- Omit braces around single-statement blocks, *unless* part of an if/else-if/else
  chain (then all branches must match).
- Prefer implicit boolean conversion: `if (str.length)`, not `if (str.length != 0)`.
  Use explicit `== 0` only when comparing a genuine number (NSRange/NSPoint), not
  emptiness.
- Multi-line conditions: put the logical operator at the **start** of the
  continuation line.
- **Four spaces, never tabs.** Trim trailing whitespace; end files with a newline.
- Commit messages: first line ≤ 72 chars (50 preferred).

Localization is managed on Transifex; `*.lproj` directories hold the translations.
Don't hand-edit translated `.strings` for languages other than English — they round-trip
through Transifex (`Tools/import_translations.py`, `travis_push_transifex.py`).

## Revival notes

This fork is being brought back to life after ~5 years of inactivity (upstream's last
commit was April 2021). Friction from age, and the decisions made so far:

### Settled (June 2026): builds on Xcode 27

The project **builds and links on Xcode 27 / macOS SDK 27** with no source changes —
every blocker was toolchain/config. What it took:

- **Toolchain.** The pinned `Gemfile` (CocoaPods `~> 1.10`, `travis ~> 1.10`) can't run
  on modern Ruby (Ruby 3.4+ dropped `mutex_m`, which CocoaPods 1.10's activesupport 5.x
  needs). Fixed by bumping `gem 'cocoapods', '~> 1.16'` and dropping the dead `travis`
  gem. Run Bundler with a modern version, e.g. `bundle _2.5.23_ install` (the old
  `BUNDLED WITH 1.17.3` pin is gone now that the lockfile was regenerated).
- **Deployment target → macOS 12.0.** Xcode 27 only supports targets >= 12.0. Raised
  in three places: the Podfile (`platform :osx, "12.0"`), a Podfile `post_install` hook
  that forces every pod target to 12.0 (several podspecs still declare 10.6–10.8), and
  the three MacDown project targets' `MACOSX_DEPLOYMENT_TARGET`. 12.0 was chosen as the
  lowest supported floor for max compatibility — revisit if newer APIs are wanted.

### Settled (June 2026): preview migrated to WKWebView

The legacy `WebView` is **gone** — the preview now runs entirely on `WKWebView`
(epic `macdown-8tk.5`, shipped across several PRs). What it took:

- **Asset loading.** A custom `WKURLSchemeHandler` (`MPAssetSchemeHandler`) serves
  preview assets and the document's own directory, since `WKWebView` won't load
  `file://` subresources from a `-loadHTMLString:baseURL:` page.
- **Async bridges.** MathJax typeset-complete and word count moved to
  `WKScriptMessageHandler` callbacks; the editor↔preview scroll-sync was rebuilt
  around an async one-round-trip metrics read (no synchronous DOM walk).
- **Cleanup.** `DOMNode+Text`, `WebView+WebViewPrivateHeaders`, `MPMathJaxListener`,
  and the legacy `Web*Delegate` conformances were deleted.

Remaining scroll-sync edge cases (the editor's per-line regex vs hoedown's block
parser — code fences, list/blockquote images, etc.) are tracked in `macdown-y9j`.

### Settled (June 2026): CI on GitHub Actions

`.github/workflows/ci.yml` builds and tests on every push to `master`, every PR,
and on demand. It runs on `macos-latest` with the **latest stable Xcode** — the
project does **not** require the Xcode 27 beta (that's only used locally for richer
MCP tooling); it's verified to build and pass tests on Xcode 26.5. The workflow
checks out submodules recursively (prism), runs
`make -C Dependency/peg-markdown-highlight` to generate `pmh_parser.c`, then
`xcodebuild test -project MacDown.xcodeproj`. Swift Packages resolve from the
committed `Package.resolved` (`-onlyUsePackageVersionsFromResolvedFile`); there is no
longer a Pods/Bundler step. The build-number script self-skips under CI and the test
target is ad-hoc signed, so tests run headless (no signing identity needed).

### Settled (June 2026): CocoaPods retired; Sparkle 2 + fork release identity

The **last CocoaPod (Sparkle) is gone**, completing the de-pod epic
(`macdown-8tk.7`). CocoaPods is fully retired — no Podfile, `Pods/`, Gemfile, or
`MacDown.xcworkspace`. What it took:

- **Sparkle 2 via SPM.** Added `github.com/sparkle-project/Sparkle` (2.9.3) as a
  remote Swift Package; its binary xcframework is **universal**, fixing the old pinned
  1.18.1 pod's x86_64-only binary that broke auto-update on Apple Silicon
  (`macdown-8tk.4`). API migrated `SUUpdater` → `SPUStandardUpdaterController`
  (`MainMenu.xib` custom object + `MPMainController` now `SPUUpdaterDelegate`). The
  two-feed stable/beta split became a single appcast with a `beta`
  `<sparkle:channel>` (`allowedChannelsForUpdater:`).
- **Two gotchas after the last pod left.** (1) Sparkle is the first *dynamic*
  framework dependency without CocoaPods, so the app needed
  `LD_RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks` added back (CocoaPods used
  to inject it) — without it dyld aborts at launch. (2) `SPUStandardUpdaterController`
  is referenced only from the nib, so a `(void)[SPUStandardUpdaterController class];`
  force-link in `-applicationDidFinishLaunching:` keeps `-dead_strip_dylibs` from
  dropping the framework.
- **Fork identity** (`macdown-8tk.8`). Bundle ids rebranded
  `com.uranusjr.*` → `com.llamagraphics.*` (project + `MPGlobals.h`); the prefs suite
  name moved too (fresh start, no migration of old defaults). Update feed now points
  at GitHub Pages (`SUFeedURL = https://samalone.github.io/macdown/appcast.xml`).
  Switched DSA → EdDSA: deleted `dsa_pub.pem`/`SUPublicDSAKeyFile`, added
  `SUPublicEDKey`. Release config signs with `Developer ID Application: Llamagraphics,
  Inc. (34CZE96W95)` + hardened runtime. The EdDSA private key and notarytool API key
  live in 1Password (pulled via `op` at release time, never persisted). The release
  pipeline (notarization + `sign_update` + appcast generation) is `macdown-8tk.8`'s
  PR 2 in `Tools/`.

### Still open

- **Smaller deprecations** (all have documented modern replacements, all local):
  `NSOnState`, `NSDragPboard`/`NSFilenamesPboardType`, `allowedFileTypes` →
  `allowedContentTypes`, `NSFileHandlingPanelOKButton`, `insertText:`,
  `unarchiveObjectWithFile:`, `colorUsingColorSpaceName:`, `base64Encoding`. The
  "function declaration without a prototype" warnings were fixed in the app and
  vendored C sources (`macdown-8tk.2`); only `macdown-cmd/main.m` still has them
  (`macdown-ayx`).


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
