#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Package author-owned donor source data, retaining the existing approved pins."""
import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUFFIXES = {'.jbeam', '.pc', '.car', '.json'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(sources, output):
    for role, src, key in [('engines', 'engine_swaps/approved-lineup.json', 'engines'),
                           ('drivetrains', 'drivetrain_conversions/approved-donors.json', 'donors')]:
        manifest = json.loads((ROOT / 'tools' / src).read_text())
        for row in manifest[key]:
            found = sorted({p.resolve() for root in sources for p in Path(root).rglob(row['archive']) if p.is_file()})
            matches = [p for p in found if digest(p.read_bytes()) == row['archiveSha256']]
            if not matches:
                raise ValueError(f"Missing approved author-owned source: {row['archive']}")
            data = io.BytesIO()
            with zipfile.ZipFile(matches[0]) as source, zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as target:
                for name in sorted(source.namelist()):
                    if name.startswith('vehicles/' + row['model'] + '/') and Path(name).suffix in SUFFIXES:
                        info = zipfile.ZipInfo(name, date_time=(2026, 10, 15, 0, 0, 0))
                        info.compress_type = zipfile.ZIP_DEFLATED
                        info.external_attr = 0o100644 << 16
                        target.writestr(info, source.read(name))
            folder = Path(output) / role
            folder.mkdir(parents=True, exist_ok=True)
            (folder / row['archive']).write_bytes(data.getvalue())
            row['originalArchiveSha256'] = row['archiveSha256']
            row['archiveSha256'] = digest(data.getvalue())
            row['provenance'] = 'Author-owned Automation export; unmodified source members, meshes/audio omitted'
        (Path(output) / (role + '.json')).write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--sources', type=Path, action='append', required=True)
    ap.add_argument('--output', type=Path, default=ROOT / 'donors/default')
    ap.add_argument('--author-owned', action='store_true', required=True,
                    help='confirm redistribution rights for all selected source vehicles')
    a = ap.parse_args()
    prepare(a.sources, a.output)
