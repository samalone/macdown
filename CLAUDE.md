# MacDown

An open-source Markdown editor for macOS, written in **Objective-C** (Cocoa/AppKit).
Live side-by-side editing with a synchronized HTML preview. Released under the MIT
License. This is a fork of [MacDownApp/macdown](https://github.com/MacDownApp/macdown),
which has been dormant since 2021 — see "Revival notes" below.

## Build & setup

There is no `Package.swift` and no SPM. The project uses **CocoaPods** (via Bundler)
plus Git submodules and a hand-built C dependency. First-time setup from the repo root:

```bash
git submodule update --init                      # fetches Dependency/prism
bundle install                                   # installs the pinned CocoaPods
bundle exec pod install                          # installs pods into Pods/
make -C Dependency/peg-markdown-highlight         # builds the PEG highlighter (C)
```

Then open **`MacDown.xcworkspace`** (NOT `MacDown.xcodeproj`) in Xcode, because the
pods live in the workspace.

- Always run CocoaPods through Bundler (`bundle exec pod ...`). The `Gemfile.lock`
  pins the supported CocoaPods version; a system-wide `pod` may be too new/old.
- Pods are sourced partly from a **patched** spec repo
  (`github.com/MacDownApp/cocoapods-specs`) — `hoedown`, `handlebars-objc`, and
  `LibYAML` come from there, not trunk. Don't "fix" the Podfile to point at upstream.
- If builds break after pulling, re-run `git submodule update` and
  `bundle exec pod install`.

### Build / test from the command line

```bash
xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build
xcodebuild -workspace MacDown.xcworkspace -scheme MacDown test
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

### Still open

- **Legacy `WebView` → `WKWebView`.** Still the big one. It currently *compiles* (the
  deprecated `WebView` is in the SDK as a warning, not an error), so it's deferrable but
  not indefinitely. The deprecated surface is concentrated in `MPDocument.m` (~30
  warnings: `WebView`, `WebFrame`, `Web*Delegate`, `DOMDocument`/`DOMNode`) and
  `Extension/DOMNode+Text.m`. `WKWebView`'s async, process-isolated model will change
  how the preview receives HTML and how the editor reads back the rendered DOM.
- **CI → GitHub Actions.** Travis (`.travis.yml`, `xcode10.1`) is defunct; the `travis`
  gem has been dropped. No replacement wired up yet.
- **Smaller deprecations** (all have documented modern replacements, all local):
  `NSOnState`, `NSDragPboard`/`NSFilenamesPboardType`, `allowedFileTypes` →
  `allowedContentTypes`, `NSFileHandlingPanelOKButton`, `insertText:`,
  `unarchiveObjectWithFile:`, `colorUsingColorSpaceName:`, `base64Encoding`, and a batch
  of "function declaration without a prototype" warnings in the C sources (`pmh_*.c`,
  `hoedown_html_patch.c`) — mechanical `(void)` fixes.
- **Bundle id / update feed** still point at the original author's domain
  (`com.uranusjr.macdown`, `macdown.uranusjr.com`); a real fork release needs its own
  Sparkle feed and signing identity (`dsa_pub.pem` is the original's).


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
