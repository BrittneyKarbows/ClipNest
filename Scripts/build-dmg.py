"""Build the image and normalize Finder's background bookmark using native metadata.

Only the background volume URL and volume flags are copied from Foundation.
Backing disk-image paths, user names and sandbox tokens are never distributed.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
import dmgbuild
from ds_store import DSStore
from mac_alias import Bookmark

parser = argparse.ArgumentParser()
parser.add_argument('--app', required=True)
parser.add_argument('--background', required=True)
parser.add_argument('--icon', required=True)
parser.add_argument('--license', required=True)
parser.add_argument('--bookmark-helper', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
mount_point = None

def callback(event):
    global mount_point
    if event.get('type') == 'command::finished' and event.get('command') == 'hdiutil::attach':
        for entity in event.get('output', {}).get('system-entities', []):
            if 'mount-point' in entity:
                mount_point = Path(entity['mount-point'])
    if event.get('type') != 'operation::finished' or event.get('operation') != 'dsstore::create':
        return
    if mount_point is None:
        raise RuntimeError('Missing mounted DMG while configuring Finder background')
    pictures = list(mount_point.glob('.background.*'))
    if len(pictures) != 1:
        raise RuntimeError('Expected exactly one installer background')
    raw = subprocess.check_output([args.bookmark_helper, 'create', str(pictures[0])])
    native = Bookmark.from_bytes(raw).tocs[0][1]
    with DSStore.open(str(mount_point / '.DS_Store'), 'r+') as store:
        bookmark = store['.']['pBBk']
        primary = bookmark.tocs[0][1]
        primary[0x2005] = native[0x2005]  # Properly escaped file URL (including non-ASCII volume names).
        primary[0x2020] = native[0x2020]  # Native local/removable volume flags.
        store['.']['pBBk'] = bookmark
        # Validate before compressing, without writing native machine-specific bookmark fields.
        with tempfile.NamedTemporaryFile() as check:
            check.write(bookmark.to_bytes()); check.flush()
            subprocess.check_call([args.bookmark_helper, 'resolve', check.name])
    subprocess.check_call(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(mount_point / 'ClipNest.app')])
    print('Validated portable Finder background bookmark and signed app.')

dmgbuild.build_dmg(str(Path(args.output).resolve()), '剪藏 ClipNest',
    settings_file=str(Path(__file__).with_name('dmg-settings.py')),
    defines={key: str(Path(getattr(args, key)).resolve()) for key in ['app', 'background', 'icon', 'license']},
    callback=callback)
