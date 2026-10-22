# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""GitHub release checks, verified staging, and stopped-server installation."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile
import time
import urllib.request
import zipfile

from net_tls import context

PLACEHOLDER = 'OWNER/REPOSITORY'
MANIFEST = 'bjrme-release.json'
MAX_DOWNLOAD = 512 * 1024 * 1024


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n', encoding='utf8')
    os.replace(temp, path)


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'v?\d+(?:\.\d+){2,3}', value):
        raise ValueError('Expected a release version such as v2.12.0.270')
    return tuple(int(n) for n in value.lstrip('v').split('.')) + (0,) * (4 - len(value.lstrip('v').split('.')))


def fetch(url, limit=2 * 1024 * 1024):
    if not re.match(r'^https://(?:api\.github\.com|github\.com|release-assets\.githubusercontent\.com|objects\.githubusercontent\.com)/', url):
        raise ValueError('Updates must use HTTPS GitHub release URLs')
    request = urllib.request.Request(url, headers={'User-Agent': 'BJRME-release-updater', 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=30, context=context()) as response:
        if not re.match(r'^https://(?:api\.github\.com|github\.com|release-assets\.githubusercontent\.com|objects\.githubusercontent\.com)/', response.geturl()):
            raise ValueError('Refusing a redirect outside HTTPS GitHub release hosts')
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Update response exceeds size limit')
    return data


def settings(root):
    folder = root / 'Resources/Server/RacePrep'
    path = folder / 'updates.json'
    if not path.exists():
        path = folder / 'updates.example.json'
    return json.loads(path.read_text(encoding='utf8')) if path.exists() else {'repository': PLACEHOLDER}


def check(root):
    cfg = settings(root)
    repo = cfg.get('repository', PLACEHOLDER)
    if repo == PLACEHOLDER or not cfg.get('enabled', False):
        return {'status': 'not-configured', 'message': 'Future release page: https://github.com/OWNER/REPOSITORY/releases; configure updates.json when published'}
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('repository must be GitHub OWNER/REPOSITORY')
    manifest = json.loads((root / MANIFEST).read_text(encoding='utf8'))
    current = manifest['version']
    # an update keeps the installed edition: Play (bundled donors) or Custom (none)
    edition = manifest.get('edition', 'play')
    if edition not in ('play', 'custom'):
        raise ValueError('Unknown installed edition in ' + MANIFEST)
    release = json.loads(fetch(f'https://api.github.com/repos/{repo}/releases/latest'))
    latest = release.get('tag_name', '')
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Only published stable releases are accepted')
    newer = version(latest) > version(current)
    platform = 'windows' if sys.platform == 'win32' else 'linux'
    assets = [a for a in release.get('assets', []) if a.get('name', '').lower() == f'bjrme-{edition}-{platform}-x64.zip']
    return {'status': 'available' if newer else 'up-to-date', 'current': current, 'latest': latest,
            'url': f'https://github.com/{repo}/releases', 'asset': assets[0] if len(assets) == 1 else None,
            'message': f'Installed {current}; latest {latest}: https://github.com/{repo}/releases'}


def allowed(name):
    p = PurePosixPath(name)
    if '\\' in name or ':' in name or p.is_absolute() or '..' in p.parts or str(p) != name:
        return False
    if name.startswith(('bjrme-generator/', 'BJRME-donors/default/', 'docs/distribution/', 'docs/methodology/', 'docs/screenshots/')):
        return True
    if name.startswith('Resources/Server/RacePrep/updater/'):
        return name == 'Resources/Server/RacePrep/updater/preflight-required.json' or name.startswith(('Resources/Server/RacePrep/updater/tools/', 'Resources/Server/RacePrep/updater/client/'))
    if p.parent.as_posix() == 'Resources/Server/RacePrep':
        return p.suffix == '.lua' or p.name in ('host.json', 'ratings-seed.json', 'rules.example.json', 'updates.example.json')
    if name.startswith('Resources/Server/BeamJoyServer/'):
        return name == 'Resources/Server/BeamJoyServer/RacePrepBJRHost.lua' or name.startswith('Resources/Server/BeamJoyServer/RacePrepBJR/')
    return name in (MANIFEST, 'Resources/Client/BJR_RacePrep.zip', 'start-bjrme-server.sh',
                    'start-bjrme-server.cmd', 'README.md', 'LICENSE', 'NOTICE', 'CHANGELOG.md',
                    'CREDITS.md', 'ROADMAP.md', 'CONTRIBUTING.md', 'GOVERNANCE.md',
                    'docs/README.md', 'docs/STATUS.md', 'docs/AUTHORSHIP.md', 'docs/artwork/banner.png')


def unpack(data, destination, expected_version):
    """Manifest hashes cover every managed member; custom exports are excluded."""
    import io
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        if sum(i.file_size for i in z.infolist()) > 2 * MAX_DOWNLOAD:
            raise ValueError('Oversized release archive')
        if len(set(z.namelist())) != len(z.namelist()) or z.testzip():
            raise ValueError('Invalid/duplicate release ZIP members')
        manifest = json.loads(z.read(MANIFEST))
        if manifest.get('format') != 1 or version(manifest['version']) != version(expected_version):
            raise ValueError('Release manifest version/format mismatch')
        members = manifest['files']
        actual = set(z.namelist()) - {MANIFEST}
        # New-install README placeholders never overwrite an administrator's custom folder.
        actual = {n for n in actual if not n.startswith('BJRME-donors/custom/')}
        if actual != set(members):
            raise ValueError('Incomplete or oversized release manifest')
        for name in [*members, MANIFEST]:
            if not allowed(name):
                raise ValueError('Release cannot overwrite this path: ' + name)
            info, content = z.getinfo(name), z.read(name)
            if name != MANIFEST and hashlib.sha256(content).hexdigest() != members[name]:
                raise ValueError('Release member checksum mismatch: ' + name)
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if info.external_attr >> 16 & 0o170000 == 0o120000:
                link = content.decode('utf8')
                if Path(link).is_absolute() or not (target.parent / link).resolve().is_relative_to(destination.resolve()):
                    raise ValueError('Unsafe release symlink: ' + name)
                target.symlink_to(link)
            else:
                target.write_bytes(content)
                target.chmod((info.external_attr >> 16 & 0o777) or 0o644)
        exe = 'bjrme-generator.exe' if sys.platform == 'win32' else 'bjrme-generator'
        if not (destination / 'bjrme-generator' / exe).is_file():
            raise ValueError('Release does not include the native updater/generator')
    return manifest


def stage(root, result):
    if result['status'] != 'available':
        return result
    asset = result.get('asset')
    if not asset:
        raise ValueError('Release has no unique native x64 archive for this edition and platform')
    expected = asset.get('digest', '')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', expected):
        raise ValueError('GitHub release asset is missing its SHA-256 digest; nothing downloaded')
    work = root / '.raceprep-update'
    if (work / 'ready.json').exists():
        raise ValueError('An update is already staged; restart through the launcher before staging another')
    work.mkdir(parents=True, exist_ok=True)
    data = fetch(asset['browser_download_url'], MAX_DOWNLOAD)
    if hashlib.sha256(data).hexdigest() != expected[7:]:
        raise ValueError('Downloaded release SHA-256 does not match GitHub')
    with tempfile.TemporaryDirectory(prefix='download-', dir=work) as tmp:
        payload = Path(tmp) / 'payload'
        unpack(data, payload, result['latest'])
        if (work / 'payload').exists():
            shutil.rmtree(work / 'payload')
        os.replace(payload, work / 'payload')
    atomic_json(work / 'ready.json', {'version': result['latest'], 'digest': expected, 'stagedAt': int(time.time())})
    return {**result, 'status': 'staged', 'message': f"Update {result['latest']} verified and staged. Stop BeamMP normally, then start through start-bjrme-server to install; no live files changed."}


def apply(root):
    """Called by the staged executable after the old server/launcher have stopped."""
    work = root / '.raceprep-update'
    if (root / 'Resources/Server/RacePrep/updater/server-session.lock').exists() or (root / 'Resources/Server/RacePrep/updater/generation.lock').exists():
        raise RuntimeError('Server/generator lock exists; stop the previous instance before applying updates')
    ready = json.loads((work / 'ready.json').read_text(encoding='utf8'))
    payload = work / 'payload'
    manifest = json.loads((payload / MANIFEST).read_text(encoding='utf8'))
    if version(manifest['version']) != version(ready['version']):
        raise ValueError('Staged release version mismatch')
    if getattr(sys, 'frozen', False) and not Path(sys.executable).resolve().is_relative_to(payload.resolve()):
        raise RuntimeError('Apply updates using the launcher, which runs the staged executable')
    files = {**manifest['files'], MANIFEST: hashlib.sha256((payload / MANIFEST).read_bytes()).hexdigest()}
    for name, expected in files.items():
        source = payload / name
        if not allowed(name) or not source.resolve().is_relative_to(payload.resolve()):
            raise ValueError('Unsafe staged path: ' + name)
        content = os.readlink(source).encode('utf8') if source.is_symlink() else source.read_bytes()
        if hashlib.sha256(content).hexdigest() != expected:
            raise ValueError('Staged file changed: ' + name)
        if not (root / name).parent.resolve().is_relative_to(root):
            raise ValueError('Installed path escapes server directory: ' + name)
    old_manifest = json.loads((root / MANIFEST).read_text(encoding='utf8')) if (root / MANIFEST).exists() else {}
    obsolete = set(old_manifest.get('files', {})) - set(files)
    for name in obsolete:
        if not allowed(name) or not (root / name).parent.resolve().is_relative_to(root):
            raise ValueError('Unsafe obsolete release path: ' + name)
    backup = work / 'backups' / (str(time.time_ns()))
    written = []
    try:
        for name in files:
            target, source = root / name, payload / name
            previous = backup / name
            existed = target.exists() or target.is_symlink()
            if existed:
                previous.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, previous, follow_symlinks=False)
            target.parent.mkdir(parents=True, exist_ok=True)
            temp = target.with_name(target.name + '.rp-update-tmp')
            if temp.exists() or temp.is_symlink():
                temp.unlink()
            if source.is_symlink():
                temp.symlink_to(os.readlink(source))
            else:
                shutil.copy2(source, temp)
            os.replace(temp, target)
            written.append((target, previous, existed))
        for name in sorted(obsolete):
            target, previous = root / name, backup / name
            if target.exists() or target.is_symlink():
                previous.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, previous, follow_symlinks=False)
                target.unlink()
                written.append((target, previous, True))
        os.replace(work / 'ready.json', work / 'applied.json')
    except Exception:
        for target, previous, existed in reversed(written):
            if target.exists() or target.is_symlink():
                target.unlink()
            if existed:
                shutil.copy2(previous, target, follow_symlinks=False)
        raise
    return {'status': 'installed', 'message': f"Installed {ready['version']}; previous files backed up in {backup}. Preflight must succeed before BeamMP starts."}


def run(root, action, request_id=None):
    root = Path(root).resolve()
    work = root / '.raceprep-update'
    if request_id is not None and not re.fullmatch(r'[0-9]+-[0-9]+', request_id):
        return {'status': 'failed', 'message': 'Invalid request ID'}
    work.mkdir(exist_ok=True)
    lock = work / 'request.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        result = {'status': 'busy', 'message': 'An update request is already running; inspect processes before removing a stale request.lock', 'requestId': request_id}
        if request_id:
            atomic_json(work / ('request-' + request_id + '.json'), result)
        return result
    try:
        try:
            result = apply(root) if action == 'apply' else check(root)
            if action == 'stage':
                result = stage(root, result)
        except Exception as e:
            result = {'status': 'failed', 'message': str(e)}
        result['requestId'] = request_id
        result['finishedAt'] = int(time.time())
        if request_id:
            atomic_json(work / ('request-' + request_id + '.json'), result)
        atomic_json(work / 'status.json', result)
        return result
    finally:
        lock.rmdir()
