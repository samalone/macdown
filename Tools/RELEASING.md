# Releasing MacDown

A MacDown release is one command. `Tools/build_for_release.py` archives a
Developer ID build, notarizes and staples it, produces a `.zip` (for Sparkle)
and a `.dmg` (for manual download), EdDSA-signs the zip, creates the GitHub
Release, and appends the new item to `docs/appcast.xml` — which GitHub Pages
serves as the live Sparkle feed.

## One-time setup

1. **Developer ID certificate.** A `Developer ID Application: Llamagraphics,
   Inc. (34CZE96W95)` certificate must be in your login keychain. The Release
   build config signs with it and enables the hardened runtime; the
   `MacDown.entitlements` exception keeps third-party plug-ins loadable.

2. **1Password items** (vault `llama-infrastructure`, via the `op` CLI):
   - `macdown-sparkle` → `private-key`: the EdDSA private key whose public half
     is `SUPublicEDKey` in `MacDown-Info.plist`. (Generated with Sparkle's
     `generate_keys`; the public half is already committed.)
   - `macdown-notarytool` → `key-id`, `issuer-id`, `api-key`: an App Store
     Connect API key for notarization. `api-key` holds the full contents of the
     `AuthKey_XXXXXXXXXX.p8` file; `key-id` is the 10-char Key ID; `issuer-id`
     is the issuer UUID. Create the key at App Store Connect → Users and Access
     → Integrations → App Store Connect API (role: at least "Developer").

   Then make the local env file (gitignored):

   ```bash
   cp Tools/release.env.example Tools/release.env
   # adjust the op:// paths if your vault/item names differ
   ```

3. **GitHub Pages.** In the repo settings → Pages, set "Build and deployment"
   to **Deploy from a branch**, branch **master**, folder **/docs**. Pages then
   serves `docs/appcast.xml` at `https://samalone.github.io/macdown/appcast.xml`
   — the `SUFeedURL` baked into the app.

4. **CLIs.** Install the 1Password CLI (`op`) and GitHub CLI (`gh`), and sign
   in to both (`eval $(op signin)`, `gh auth login`).

## Cutting a release

1. Bump `Tools/version.txt` if the marketing version is changing, and commit.

2. Tag the release commit so the build picks up a clean version (the version
   strings are derived from `git describe`):

   ```bash
   git tag v0.9.0
   ```

3. Run the pipeline through `op run` so the 1Password references resolve into
   the environment (and nowhere else):

   ```bash
   op run --env-file=Tools/release.env -- python3 Tools/build_for_release.py
   ```

   It will, in order: clean, build the PEG highlighter, archive + export the
   signed app, notarize and staple it, build `MacDown-<ver>.zip` and
   `MacDown-<ver>.dmg`, EdDSA-sign the zip, create GitHub Release `v<ver>` with
   both artifacts, append the item to `docs/appcast.xml`, and commit + push that
   change. Installed copies pick up the update on their next Sparkle check.

### Dry run

To exercise everything locally without touching Apple, GitHub, or git:

```bash
op run --env-file=Tools/release.env -- python3 Tools/build_for_release.py --dry-run
```

This still archives, exports, builds the artifacts, and EdDSA-signs the zip
(so it needs `SPARKLE_PRIVATE_KEY`), then prints the artifact paths and the
appcast `<item>` it *would* publish — but skips notarization, the Release, and
the appcast commit. Useful flags: `--skip-notarize` (notarized already) and
`--no-push` (commit the feed but push it yourself).

## Notes

- **Secrets never persist.** The EdDSA key is piped to `sign_update
  --ed-key-file -` on stdin; the notarytool `.p8` is written to a mode-0600
  temp file only for the notarytool run and removed immediately. Nothing is
  written to the keychain.
- **`sign_update` location.** The script finds Sparkle's `sign_update` under
  DerivedData automatically. If Xcode hasn't resolved the package yet, build
  MacDown once, or set `SPARKLE_BIN_DIR` to the directory containing it.
- **Feed stays on master.** `docs/appcast.xml` is committed to `master`, so the
  published feed always matches the released source.
