#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Build, sign, notarize, and publish a MacDown release.

One command takes a Developer ID build all the way to a live Sparkle update:

    archive -> export -> notarize -> staple -> zip + dmg
            -> EdDSA-sign the zip -> GitHub Release -> update docs/appcast.xml

Secrets come from 1Password via `op run`, so they never touch disk or the
keychain. Run it as:

    op run --env-file=Tools/release.env -- python3 Tools/build_for_release.py

See Tools/RELEASING.md for the full runbook (1Password layout, GitHub Pages,
tagging) and Tools/release.env.example for the expected environment.

Environment (resolved by `op run`):
    SPARKLE_PRIVATE_KEY   EdDSA private key, piped to `sign_update` on stdin.
    AC_API_KEY_ID         App Store Connect API Key ID (notarytool).
    AC_API_ISSUER_ID      App Store Connect issuer UUID (notarytool).
    AC_API_KEY            Contents of the AuthKey_*.p8 file (notarytool).

Optional environment:
    SPARKLE_BIN_DIR       Directory holding Sparkle's `sign_update`. Auto-
                          discovered under DerivedData when unset.

The Sparkle EdDSA key and the notarytool .p8 are written to mode-0600 temp
files only for the tools that need a file, and removed in a finally block.
"""

from __future__ import print_function

import argparse
import glob
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from email.utils import format_datetime

from macdown_utils import ROOT_DIR, XCODEBUILD


TEAM_ID = '34CZE96W95'
GITHUB_REPO = 'samalone/macdown'
APPCAST_PATH = os.path.join(ROOT_DIR, 'docs', 'appcast.xml')
APPCAST_MARKER = '<!-- RELEASE ITEMS BELOW'
DOWNLOAD_URL_TEMPLATE = (
    'https://github.com/{repo}/releases/download/{tag}/{name}'
)

BUILD_DIR = os.path.join(ROOT_DIR, 'Build')
ARCHIVE_PATH = os.path.join(BUILD_DIR, 'MacDown.xcarchive')
EXPORT_DIR = os.path.join(BUILD_DIR, 'export')
APP_NAME = 'MacDown.app'
MIN_SYSTEM_VERSION = '12.0'


def log(message):
    print('==> {0}'.format(message))


def run(*args, **kwargs):
    """Run a command, streaming its output to the terminal."""
    printable = ' '.join(args)
    log(printable if len(printable) < 200 else printable[:197] + '...')
    subprocess.check_call(args, **kwargs)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--dry-run', action='store_true',
        help='Build, sign, and generate the appcast entry locally, but skip '
             'notarization, the GitHub Release, and the appcast commit/push. '
             'Use to validate the pipeline without touching Apple or GitHub.',
    )
    parser.add_argument(
        '--skip-notarize', action='store_true',
        help='Skip notarization + stapling only (still releases and updates '
             'the feed). For iterating when the build is already notarized.',
    )
    parser.add_argument(
        '--no-push', action='store_true',
        help='Commit the appcast update but do not push it to the remote.',
    )
    return parser.parse_args(argv)


def require_env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(
            'error: {0} is not set. Run through `op run --env-file='
            'Tools/release.env` (see Tools/RELEASING.md).'.format(name)
        )
    return value


def find_sign_update():
    """Locate Sparkle's `sign_update`, honoring SPARKLE_BIN_DIR."""
    override = os.environ.get('SPARKLE_BIN_DIR')
    if override:
        candidate = os.path.join(override, 'sign_update')
        if os.path.isfile(candidate):
            return candidate
        sys.exit('error: no sign_update in SPARKLE_BIN_DIR ({0}).'
                 .format(override))
    pattern = os.path.expanduser(
        '~/Library/Developer/Xcode/DerivedData/'
        'MacDown-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update'
    )
    matches = sorted(glob.glob(pattern))
    if not matches:
        sys.exit(
            'error: could not find Sparkle\'s sign_update under DerivedData. '
            'Build MacDown once so Xcode resolves the Sparkle package, or set '
            'SPARKLE_BIN_DIR to the directory containing sign_update.'
        )
    return matches[-1]


def write_temp(content, suffix):
    """Write content to a private (0600) temp file; caller must remove it."""
    fd, path = tempfile.mkstemp(suffix=suffix, dir=BUILD_DIR)
    os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR)
    with os.fdopen(fd, 'w') as f:
        f.write(content)
    return path


def clean_build_dir():
    log('Pre-build cleaning...')
    if os.path.exists(BUILD_DIR):
        shutil.rmtree(BUILD_DIR, ignore_errors=True)
    os.makedirs(BUILD_DIR)
    run(XCODEBUILD, 'clean', '-project', 'MacDown.xcodeproj',
        '-scheme', 'MacDown', cwd=ROOT_DIR)


def build_peg_highlighter():
    log('Building the bundled PEG highlighter...')
    run('make', '-C', os.path.join(ROOT_DIR, 'Dependency',
                                   'peg-markdown-highlight'))


def archive_and_export():
    log('Archiving (Release, Developer ID)...')
    run(XCODEBUILD, 'archive',
        '-project', 'MacDown.xcodeproj',
        '-scheme', 'MacDown',
        '-configuration', 'Release',
        '-destination', 'generic/platform=macOS',
        '-archivePath', ARCHIVE_PATH,
        '-onlyUsePackageVersionsFromResolvedFile',
        cwd=ROOT_DIR)

    options = {
        'method': 'developer-id',
        'teamID': TEAM_ID,
        'signingStyle': 'manual',
        # With manual signing, name the certificate explicitly; otherwise
        # -exportArchive can fail to resolve a Developer ID identity.
        'signingCertificate': 'Developer ID Application',
    }
    options_path = os.path.join(BUILD_DIR, 'ExportOptions.plist')
    with open(options_path, 'wb') as f:
        plistlib.dump(options, f)

    log('Exporting the signed app...')
    run(XCODEBUILD, '-exportArchive',
        '-archivePath', ARCHIVE_PATH,
        '-exportPath', EXPORT_DIR,
        '-exportOptionsPlist', options_path,
        cwd=ROOT_DIR)
    return os.path.join(EXPORT_DIR, APP_NAME)


def read_versions(app_path):
    info_path = os.path.join(app_path, 'Contents', 'Info.plist')
    with open(info_path, 'rb') as f:
        info = plistlib.load(f)
    short = info['CFBundleShortVersionString']
    bundle = info['CFBundleVersion']
    return short, bundle


def make_zip(app_path, zip_path):
    if os.path.exists(zip_path):
        os.remove(zip_path)
    # ditto preserves symlinks and resource forks the way Sparkle expects.
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
        app_path, zip_path)


def notarize(zip_path):
    key_id = require_env('AC_API_KEY_ID')
    issuer = require_env('AC_API_ISSUER_ID')
    key_pem = require_env('AC_API_KEY')
    key_path = write_temp(key_pem, '.p8')
    try:
        log('Submitting to notarytool (this can take a few minutes)...')
        proc = subprocess.run(
            ['xcrun', 'notarytool', 'submit', zip_path,
             '--key', key_path, '--key-id', key_id, '--issuer', issuer,
             '--wait'],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
    finally:
        os.remove(key_path)
    output = proc.stdout.decode('utf-8', 'replace')
    print(output)
    # `notarytool --wait` does not reliably exit nonzero on a rejected
    # submission, so check the reported status explicitly rather than trusting
    # the return code (a later stapler failure would otherwise be the only,
    # confusing, signal).
    if proc.returncode or 'status: Accepted' not in output:
        sys.exit('error: notarization did not succeed (see output above). '
                 'Inspect with `xcrun notarytool log <submission-id> --key '
                 '<p8> --key-id <id> --issuer <uuid>`.')


def staple(target):
    log('Stapling {0}...'.format(os.path.basename(target)))
    run('xcrun', 'stapler', 'staple', target)


def make_dmg(app_path, dmg_path):
    if os.path.exists(dmg_path):
        os.remove(dmg_path)
    # Stage the app next to an /Applications symlink for drag-install.
    stage = os.path.join(BUILD_DIR, 'dmg')
    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(stage)
    shutil.copytree(app_path, os.path.join(stage, APP_NAME), symlinks=True)
    os.symlink('/Applications', os.path.join(stage, 'Applications'))
    log('Building {0}...'.format(os.path.basename(dmg_path)))
    run('/usr/bin/hdiutil', 'create', '-volname', 'MacDown',
        '-srcfolder', stage, '-ov', '-format', 'UDZO', dmg_path)
    shutil.rmtree(stage)


def sign_update(zip_path):
    sign_update_bin = find_sign_update()
    key = require_env('SPARKLE_PRIVATE_KEY')
    log('Signing the update archive with EdDSA...')
    # Pipe the key on stdin via `--ed-key-file -`, the approach Sparkle
    # recommends for an env-var secret: the key never hits disk, the keychain,
    # or the process argument list. (`-s` is deprecated and rejected for
    # newly generated keys.)
    proc = subprocess.Popen(
        [sign_update_bin, zip_path, '--ed-key-file', '-'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    stdout, stderr = proc.communicate(input=(key + '\n').encode('utf-8'))
    if proc.returncode:
        sys.exit('error: sign_update failed: {0}'
                 .format(stderr.decode('utf-8', 'replace').strip()))
    # Prints e.g.:  sparkle:edSignature="..." length="12345"
    return stdout.decode('utf-8').strip()


def appcast_item(short, bundle, signature_attrs, url, pub_date):
    return (
        '        <item>\n'
        '            <title>Version {short}</title>\n'
        '            <pubDate>{date}</pubDate>\n'
        '            <sparkle:version>{bundle}</sparkle:version>\n'
        '            <sparkle:shortVersionString>{short}'
        '</sparkle:shortVersionString>\n'
        '            <sparkle:minimumSystemVersion>{minsys}'
        '</sparkle:minimumSystemVersion>\n'
        '            <enclosure url="{url}" type="application/octet-stream" '
        '{sig}/>\n'
        '        </item>\n'
    ).format(short=short, bundle=bundle, date=pub_date, url=url,
             sig=signature_attrs, minsys=MIN_SYSTEM_VERSION)


def insert_appcast_item(item_xml):
    with open(APPCAST_PATH, 'r') as f:
        text = f.read()
    marker = text.find(APPCAST_MARKER)
    if marker == -1:
        sys.exit('error: insertion marker missing from {0}.'
                 .format(APPCAST_PATH))
    comment_close = text.find('-->', marker)
    if comment_close == -1:
        sys.exit('error: malformed insertion marker in {0}.'
                 .format(APPCAST_PATH))
    cut = text.index('\n', comment_close) + 1
    updated = text[:cut] + item_xml + text[cut:]
    with open(APPCAST_PATH, 'w') as f:
        f.write(updated)


def github_release(tag, short, artifacts):
    log('Creating GitHub Release {0}...'.format(tag))
    run('gh', 'release', 'create', tag,
        '--repo', GITHUB_REPO,
        '--title', 'MacDown {0}'.format(short),
        '--notes', 'MacDown {0}. Delivered via Sparkle.'.format(short),
        *artifacts)


def commit_appcast(tag, push):
    run('git', 'add', APPCAST_PATH, cwd=ROOT_DIR)
    run('git', 'commit', '-m',
        'Publish {0} to the Sparkle appcast'.format(tag), cwd=ROOT_DIR)
    if push:
        run('git', 'push', cwd=ROOT_DIR)
    else:
        log('--no-push: appcast committed locally; push it yourself.')


def main(argv=None):
    options = parse_args(argv)
    if not options.dry_run:
        # Fail fast if secrets are missing before doing a long build.
        require_env('SPARKLE_PRIVATE_KEY')
        if not options.skip_notarize:
            require_env('AC_API_KEY_ID')
            require_env('AC_API_ISSUER_ID')
            require_env('AC_API_KEY')

    clean_build_dir()
    build_peg_highlighter()
    app_path = archive_and_export()
    short, bundle = read_versions(app_path)
    if short == '0.1' or not short:
        sys.exit(
            'error: exported app version is "{0}" — the git-derived version '
            'was not injected (Info.plist still holds its placeholder). Tag '
            'the release commit (e.g. `git tag v0.9.0`) before building; see '
            'Tools/RELEASING.md.'.format(short)
        )
    tag = 'v{0}'.format(short)
    log('Building MacDown {0} (bundle {1}), tag {2}.'
        .format(short, bundle, tag))

    zip_name = 'MacDown-{0}.zip'.format(short)
    dmg_name = 'MacDown-{0}.dmg'.format(short)
    zip_path = os.path.join(BUILD_DIR, zip_name)
    dmg_path = os.path.join(BUILD_DIR, dmg_name)

    if options.dry_run or options.skip_notarize:
        log('Skipping notarization' +
            (' (dry run)' if options.dry_run else ' (--skip-notarize)') + '.')
    else:
        notarize_zip = os.path.join(BUILD_DIR, 'notarize.zip')
        make_zip(app_path, notarize_zip)
        notarize(notarize_zip)
        os.remove(notarize_zip)
        staple(app_path)

    # Final, stapled artifacts.
    make_zip(app_path, zip_path)
    make_dmg(app_path, dmg_path)

    signature_attrs = sign_update(zip_path)
    url = DOWNLOAD_URL_TEMPLATE.format(repo=GITHUB_REPO, tag=tag, name=zip_name)
    pub_date = format_datetime(datetime.now(timezone.utc))
    item_xml = appcast_item(short, bundle, signature_attrs, url, pub_date)

    if options.dry_run:
        log('Dry run complete. Artifacts in {0}:'.format(BUILD_DIR))
        print('  {0}\n  {1}'.format(zip_path, dmg_path))
        log('Appcast item that WOULD be published:')
        print(item_xml)
        return

    github_release(tag, short, [zip_path, dmg_path])
    insert_appcast_item(item_xml)
    commit_appcast(tag, push=not options.no_push)
    log('Released {0}. Feed updated at docs/appcast.xml.'.format(tag))


if __name__ == '__main__':
    main()
