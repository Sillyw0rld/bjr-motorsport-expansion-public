#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Build a BeamJoy-Revived: Motorsport Expansion release zip.

The release contains only the expansion. BeamJoy-Revived itself, BeamMP and the
car mods are installed separately. Upgrade parts for Automation cars are not
shipped: the bundled parts generator (the conversion tool) builds them on the
server for the cars it has. Two editions, the same everywhere else:
  play    with the bundled conversion donors (engines, FWD / RWD / AWD): engine
          and drivetrain conversions work out of the box
  custom  without them: the administrator adds their own donor cars in
          BJRME-donors/custom/ (drivetrain conversions need one FWD, one
          RWD and one AWD donor)

Layout (extract into the BeamMP server folder):
  Resources/Client/BJR_RacePrep.zip      client mod (players download it)
  Resources/Server/RacePrep/             server plugin + updater (the generator's data)
  BJRME-donors/                       default (play) and custom donor folders
Nothing is added to BeamJoy-Revived's folders.

usage: python3 -I build_release.py --edition play|custom [--output dist/<name>.zip] [-v]
"""
import argparse
import hashlib
import io
import json
import os
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = 'bjr-motorsport-expansion'
VERSION = (ROOT / 'VERSION').read_text().strip()  # one version for the live build and the public release
EDITIONS = ('play', 'custom')
SERVER_FILES = {'RacePrep.lua', 'BJRHost.lua', 'BJRApi.lua', 'RatingStore.lua', 'RatingIdentity.lua', 'Skill.lua', 'Sessions.lua',
                'RaceControl.lua', 'RubberMap.lua', 'MarbleMap.lua',  'DriverStats.lua', 'Championship.lua',
                'ResultHistory.lua', 'PartsUpdater.lua', 'ReleaseUpdates.lua', 'MotorsportSettings.lua', 'Weekend.lua', 'updates.example.json', 'ratings-seed.json', 'rules.example.json'}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def files(root):
    return sorted(p for p in root.rglob('*') if p.is_file() and '__pycache__' not in p.parts)


def archive(items, symlinks=()):
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w') as z:
        for name, data in sorted(items.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 15, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o120777 if name in symlinks else (0o100755 if name.endswith('.sh') or name == 'bjrme-generator/bjrme-generator' else 0o100644)
            info.external_attr = mode << 16
            z.writestr(info, data)
    return out.getvalue()


def build(output, verbose=False, generator_dir=None, source_only=False, edition='play'):
    if edition not in EDITIONS:
        raise ValueError('edition must be play or custom')
    if not source_only and generator_dir is None:
        raise ValueError('Public releases require --generator-dir from a native build; use --source-only for developers')
    build_no = int(git('rev-list', '--count', 'HEAD'))
    commit = git('rev-parse', 'HEAD')
    dirty = bool(git('status', '--porcelain'))
    version = f'{VERSION}.{build_no}'
    client = {}
    for p in files(ROOT / 'client'):
        name = p.relative_to(ROOT / 'client').as_posix()
        if name.startswith('lua/ge/extensions/BJI/') or name.startswith('vehicles/'):
            continue  # legacy ImGui windows; generated parts are made per server
        if name.startswith('native/vehicles/'):
            name = name[len('native/'):]  # BeamNG cars' parts ship ready-made, both editions
        client[name] = p.read_bytes()
    client['lua/ge/extensions/raceprep/version.json'] = json.dumps({'version': version, 'commit': commit[:7], 'dirty': dirty}).encode()
    client['mod_info.json'] = json.dumps({'name': 'BeamJoy-Revived: Motorsport Expansion', 'version': version, 'author': 'Sillyw0rld',
                                          'license': 'AGPL-3.0-or-later'}, indent=2).encode()
    for name in ('LICENSE', 'NOTICE', 'CREDITS.md'):
        client[name] = (ROOT / name).read_bytes()
    client['docs/AUTHORSHIP.md'] = (ROOT / 'docs/AUTHORSHIP.md').read_bytes()
    payload = {'Resources/Client/BJR_RacePrep.zip': archive(client)}
    for p in files(ROOT / 'server/RacePrep'):
        if p.name in SERVER_FILES:
            payload['Resources/Server/RacePrep/' + p.name] = p.read_bytes()
    for p in files(ROOT / 'tools'):
        if p.suffix in ('.py', '.json', '.lua'):
            payload['Resources/Server/RacePrep/updater/tools/' + p.relative_to(ROOT / 'tools').as_posix()] = p.read_bytes()
    for p in files(ROOT / 'client/lua'):
        if p.suffix == '.json':
            payload['Resources/Server/RacePrep/updater/client/lua/' + p.relative_to(ROOT / 'client/lua').as_posix()] = p.read_bytes()
    # play: the bundled donors; custom: none (the administrator's own only)
    if edition == 'play':
        for p in files(ROOT / 'donors/default'):
            payload['BJRME-donors/default/' + p.relative_to(ROOT / 'donors/default').as_posix()] = p.read_bytes()
    for role in ('engines', 'drivetrains'):
        payload['BJRME-donors/custom/' + role + '/README.txt'] = (ROOT / 'donors/custom' / role / 'README.txt').read_bytes()
    payload['Resources/Server/RacePrep/updater/preflight-required.json'] = b'{"version":1}\n'
    links = set()
    if generator_dir:
        generator_dir = Path(generator_dir)
        executable = generator_dir / ('bjrme-generator.exe' if (generator_dir / 'bjrme-generator.exe').exists() else 'bjrme-generator')
        if not executable.is_file():
            raise ValueError('Missing native standalone generator in ' + str(generator_dir))
        for p in sorted(p for p in generator_dir.rglob('*') if p.is_file() or p.is_symlink()):
            name = 'bjrme-generator/' + p.relative_to(generator_dir).as_posix()
            if p.is_symlink():
                target = os.readlink(p)
                if Path(target).is_absolute() or not (p.parent / target).resolve().is_relative_to(generator_dir.resolve()):
                    raise ValueError('Unsafe standalone symlink: ' + name)
                links.add(name)
                payload[name] = target.encode('utf8')
            else:
                payload[name] = p.read_bytes()
        launcher = 'start-bjrme-server.cmd' if executable.suffix == '.exe' else 'start-bjrme-server.sh'
        payload[launcher] = (ROOT / 'packaging' / launcher).read_bytes()
    for folder in ('distribution', 'methodology', 'screenshots'):
        for p in files(ROOT / 'docs' / folder):
            payload['docs/' + folder + '/' + p.relative_to(ROOT / 'docs' / folder).as_posix()] = p.read_bytes()
    payload['docs/artwork/banner.png'] = (ROOT / 'docs/artwork/banner.png').read_bytes()  # README banner
    for name in ('README.md', 'STATUS.md', 'AUTHORSHIP.md'):
        payload['docs/' + name] = (ROOT / 'docs' / name).read_bytes()
    payload['Resources/Server/RacePrep/host.json'] = (json.dumps({'host': 'beamjoy-revived', 'protocol': 1, 'version': version}) + '\n').encode()
    for name in ('LICENSE', 'NOTICE', 'README.md', 'CHANGELOG.md', 'CREDITS.md',
                 'ROADMAP.md', 'CONTRIBUTING.md', 'GOVERNANCE.md'):
        payload[name] = (ROOT / name).read_bytes()
    manifest = {'format': 1, 'version': version, 'edition': edition, 'commit': commit, 'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items()) if not name.startswith('BJRME-donors/custom/')}}
    payload['bjrme-release.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    output = Path(output or ROOT / 'dist' / f'{NAME}-{version}-{edition}.zip')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(archive(payload, symlinks=links))
    with zipfile.ZipFile(output) as z:
        assert z.testzip() is None
    if verbose:
        for name in sorted(payload):
            print(f'  {len(payload[name]):>10}  {name}')
    print(json.dumps({'archive': str(output), 'version': version, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                      'edition': edition, 'bytes': output.stat().st_size, 'commit': commit, 'dirty': dirty}, indent=2))


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--output', type=Path)
    ap.add_argument('-v', '--verbose', action='store_true')
    ap.add_argument('--generator-dir', type=Path, help='native PyInstaller onedir distribution')
    ap.add_argument('--source-only', action='store_true', help='developer archive, requires Python; not a public standalone release')
    ap.add_argument('--edition', choices=EDITIONS, default='play',
                    help='play: with the bundled conversion donors; custom: without (the administrator adds their own)')
    a = ap.parse_args()
    build(a.output, a.verbose, a.generator_dir, a.source_only, a.edition)
