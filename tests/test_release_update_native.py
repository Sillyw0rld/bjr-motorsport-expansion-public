# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Native executable replacement gate; uses a local release, no network/server."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import release_updates as U


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    if not args.archive:
        print('SKIP: native release-update gate requires --archive')
        return
    data = args.archive.read_bytes()
    with zipfile.ZipFile(args.archive) as z:
        manifest = json.loads(z.read(U.MANIFEST))
        current, edition = manifest['version'], manifest.get('edition', 'play')
        # BeamNG cars' ready-made parts ship in the client mod and are validated too
        import io
        with zipfile.ZipFile(io.BytesIO(z.read('Resources/Client/BJR_RacePrep.zip'))) as client:
            names = client.namelist()
            native_parts = len(json.loads(client.read('lua/ge/extensions/raceprep/native-parts.json'))['parts']) if 'lua/ge/extensions/raceprep/native-parts.json' in names else 0
    with tempfile.TemporaryDirectory(prefix='rp native update é ') as tmp:
        server = Path(tmp).resolve() / 'server install'
        U.unpack(data, server, current)
        # one real Automation car to generate for: a bundled donor (Play) or the
        # same export from the source tree (Custom ships no donors)
        car = server / 'BJRME-donors/default/engines/hawk_el_chapo.zip'
        shutil.copyfile(car if edition == 'play' else ROOT / 'donors/default/engines/hawk_el_chapo.zip', server / 'Resources/Client/car.zip')
        custom = server / 'BJRME-donors/custom/engines/owner.keep'
        custom.parent.mkdir(parents=True);custom.write_bytes(b'keep')
        rules = server / 'Resources/Server/RacePrep/rules.json';rules.write_bytes(b'{"keep":true}')
        import hashlib
        result = {'status': 'available', 'latest': current, 'asset': {'browser_download_url': 'https://github.com/author/project/releases/download/test/native.zip', 'digest': 'sha256:' + hashlib.sha256(data).hexdigest()}}
        with patch.object(U, 'fetch', return_value=data):
            assert U.stage(server, result)['status'] == 'staged'
        exe = 'bjrme-generator.exe' if sys.platform == 'win32' else 'bjrme-generator'
        env = dict(os.environ, PATH='', PYTHONPATH='', PYTHONHOME='')
        staged = server / '.raceprep-update/payload/bjrme-generator' / exe
        apply = subprocess.run([str(staged), '--beammp', str(server), '--update-apply'], cwd=tmp,
                               env=env, capture_output=True, text=True, encoding='utf8', timeout=180)
        assert apply.returncode == 0, apply.stdout + apply.stderr
        native = server / 'bjrme-generator' / exe
        generation = subprocess.run([str(native), '--beammp', str(server)], cwd=tmp,
                                    env=env, capture_output=True, text=True, encoding='utf8', timeout=180)
        assert generation.returncode == 0, generation.stdout + generation.stderr
        # Play: the car plus its engine and drivetrain conversions; Custom: no donors, no conversions
        import re
        parts = re.search(r'Validated (\d+) parts', generation.stdout)
        assert parts, generation.stdout
        generated = int(parts.group(1)) - native_parts
        if edition == 'play':
            assert generated == 571, generation.stdout
        else:
            assert 0 < generated < 571, generation.stdout
        assert custom.read_bytes() == b'keep' and rules.read_bytes() == b'{"keep":true}'
        assert not (server / '.raceprep-update/ready.json').exists()
        assert (server / '.raceprep-update/applied.json').exists()
        print(f'PASS ({edition}): staged native executable replaces installed bundle, then generates parts with empty PATH; custom/settings retained; no network or BeamMP launched')


if __name__ == '__main__':
    main()
