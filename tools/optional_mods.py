# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Optional mods BJR:ME works with: detection, reminders, verified download.

Nothing here is bundled. `get` downloads a mod from its official page, accepts
it only when its SHA-256 matches the version BJR:ME was tested with, and stages
it; the next launcher start installs it (stopped server, backups, mods.json).
Owners who don't want a mod list it in RacePrep/optional-mods.json "ignore".
"""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import time
import urllib.request
import zipfile

from net_tls import context

MODS = {
    'kts': {
        'name': "Kagoni's Tyre Simulation", 'author': 'Kagoni', 'resource': 39079, 'version': '1.5.0-HOTFIX 2',
        'page': 'https://www.beamng.com/resources/kagoni%E2%80%99s-tyre-simulation.39079/',
        'url': 'https://www.beamng.com/resources/kagoni%E2%80%99s-tyre-simulation.39079/download?version=72880',
        'sha256': '2f2c74db0602db63c5fa40a1cd6cdc28c286d07c8511c8fd48ef463ef4cdaad0',
        'client': 'Kagoni_Tyre_Simulation.zip', 'marker': 'lua/ge/extensions/career/modules/kagoniTyrePersistence.lua',
        'why': 'tyre heat and wear; BJR:ME tyre compounds, rubbered-line grip and track temperature work through it',
    },
    'fluidspill': {
        'name': 'Fluid Spill Mod', 'author': 'Dirt 2', 'resource': 38681, 'version': '1.3.0',
        'page': 'https://www.beamng.com/resources/fluid-spill-mod.38681/',
        # the author's project pack: client zip and BeamMP server plugin together
        'url': 'https://download.milospeelman.nl/s/tnLjFJlypsJCCPa/download',
        'sha256': '0e64f43f13f0566a108e3e7f1816bd2c7f093d3dab5bb1076396a82a342dab10',
        'client': 'fluidspill-100.zip', 'marker': 'lua/ge/extensions/fluidspill/main.lua',
        'client_sha256': '4a2f5d2a76b3964261abfcd295cb945953e0031917d171200728e65c351fc042',
        'pack_client': 'Fluid Spill Mod/fluid-spill-1.3.0-project-files/dist/1.3.0/fluidspill-100.zip',
        'pack_server': 'Fluid Spill Mod/fluid-spill-1.3.0-project-files/beammp/Resources/Server/FluidSpill/',
        'server': 'Resources/Server/FluidSpill',
        'why': 'oil, coolant and fuel spills shared between players (its own server plugin is installed with it)',
    },
    'ddp': {
        'name': 'Dynamic Damage Particles', 'author': 'samllea1', 'resource': 38670, 'version': '2.0',
        'page': 'https://www.beamng.com/resources/dynamic-damage-particles.38670/',
        'url': 'https://www.beamng.com/resources/dynamic-damage-particles.38670/download?version=71262',
        'sha256': '451f2d1849e7e1e854bdf11b23f05f982dcfc45751a54c0e8d01c4c4eae95f61',
        'client': 'dynamic_damage_particles.zip', 'marker': 'lua/ge/extensions/crashDebris.lua',
        'why': 'crash debris',
    },
}
HOSTS = r'^https://(?:www\.beamng\.com|[0-9a-f]+\.r2\.cloudflarestorage\.com|download\.milospeelman\.nl)/'
MAX_DOWNLOAD = 64 * 1024 * 1024
WORK = '.bjrme-optional'


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n', encoding='utf8')
    os.replace(temp, path)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ignored(root):
    path = root / 'Resources/Server/RacePrep/optional-mods.json'
    try:
        data = json.loads(path.read_text(encoding='utf8'))
    except (OSError, ValueError):
        return set()
    return {k for k in data.get('ignore', []) if k in MODS}


def identify(path):
    """(key, version or None) of a client zip, or (None, None)."""
    try:
        data = path.read_bytes()
        z = zipfile.ZipFile(io.BytesIO(data))
        names = set(z.namelist())
    except (OSError, zipfile.BadZipFile):
        return None, None
    digest = sha(data)
    for key, m in MODS.items():
        if digest in (m['sha256'], m.get('client_sha256')):
            return key, m['version']
    for n in names:
        if n.startswith('mod_info/') and n.endswith('/info.json'):
            try:
                info = json.loads(z.read(n))
            except ValueError:
                continue
            for key, m in MODS.items():
                if info.get('resource_id') == m['resource']:
                    return key, str(info.get('version_string') or '') or None
    for key, m in MODS.items():
        if m['marker'] in names:
            return key, None
    return None, None


def detect(root):
    """Status of every optional mod: missing, outdated, current or unknown version."""
    root = Path(root)
    found = {}
    for path in sorted((root / 'Resources/Client').glob('*.zip')):
        key, ver = identify(path)
        if key and key not in found:
            found[key] = {'file': path.name, 'version': ver}
    skip = ignored(root)
    out = []
    for key, m in MODS.items():
        f = found.get(key)
        if not f:
            state = 'missing'
        elif f['version'] == m['version']:
            state = 'current'
        elif f['version'] is None:
            state = 'unknown'
        else:
            state = 'outdated'
        if state == 'current' and m.get('server') and not (root / m['server'] / 'main.lua').exists():
            state = 'plugin-missing'
        out.append({'key': key, 'name': m['name'], 'state': state, 'installed': f and f['version'], 'file': f and f['file'],
                    'latest': m['version'], 'page': m['page'], 'why': m['why'], 'ignored': key in skip})
    return out


def lines(status):
    """Console reminders for mods that are not ignored."""
    text = {'missing': 'not installed', 'outdated': 'installed {installed}, tested with {latest}',
            'unknown': 'installed (version not recognised), tested with {latest}', 'plugin-missing': 'its BeamMP server plugin is missing'}
    out = []
    for s in status:
        if s['ignored'] or s['state'] == 'current':
            continue
        out.append(f"Optional: {s['name']} {text[s['state']].format(**s)} ({s['why']}). Page: {s['page']} . "
                   f"Type \"bjrme get {s['key']}\" to download it, or \"bjrme optional ignore {s['key']}\" to stop this reminder.")
    return out


def report(root):
    """Write the status file the plugin and Motorsport settings read; return reminder lines."""
    root = Path(root)
    status = detect(root)
    reminders = lines(status)
    atomic_json(root / 'Resources/Server/RacePrep/optional-mods-status.json', {'checkedAt': int(time.time()), 'mods': status, 'reminders': reminders})
    return reminders


def fetch(url):
    if not re.match(HOSTS, url):
        raise ValueError('Optional mods download only from their official pages')
    request = urllib.request.Request(url, headers={'User-Agent': 'BJRME-optional-mods'})
    with urllib.request.urlopen(request, timeout=60, context=context()) as response:
        if not re.match(HOSTS, response.geturl()):
            raise ValueError('Refusing a redirect away from the official download hosts')
        data = response.read(MAX_DOWNLOAD + 1)
    if len(data) > MAX_DOWNLOAD:
        raise ValueError('Download exceeds the size limit')
    return data


def get(root, key, download=fetch):
    """Download, verify and stage one mod for the next launcher start."""
    root = Path(root)
    if key not in MODS:
        return {'status': 'failed', 'message': 'Unknown optional mod; choose one of: ' + ', '.join(MODS)}
    m = MODS[key]
    data = download(m['url'])
    if sha(data) != m['sha256']:
        return {'status': 'failed', 'message': f"{m['name']}: the download does not match version {m['version']} that BJR:ME was tested with (its page may have a newer version); nothing was staged"}
    stage = root / WORK / 'staged' / key
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    if key == 'fluidspill':
        z = zipfile.ZipFile(io.BytesIO(data))
        (stage / m['client']).write_bytes(z.read(m['pack_client']))
        for n in z.namelist():
            if n.startswith(m['pack_server']) and not n.endswith('/'):
                rel = n[len(m['pack_server']):]
                if '/' in rel or '..' in rel or not rel:
                    continue
                (stage / 'server').mkdir(exist_ok=True)
                (stage / 'server' / rel).write_bytes(z.read(n))
    else:
        (stage / m['client']).write_bytes(data)
    atomic_json(stage / 'plan.json', {'key': key, 'version': m['version'], 'client': m['client']})
    return {'status': 'staged', 'message': f"{m['name']} {m['version']} verified and staged; it installs at the next launcher start"}


def update_mods_json(root, path):
    mods = root / 'Resources/Client/mods.json'
    if not mods.exists():
        return
    d = json.loads(mods.read_text(encoding='utf8'))
    entry = d.setdefault(path.name, {'protected': False})
    entry.update(filesize=path.stat().st_size, hash=sha(path.read_bytes()),
                 lastwrite=path.stat().st_mtime_ns // 100 + 116444736000000000)
    temp = mods.with_suffix('.json.tmp')
    temp.write_text(json.dumps(d, indent=4) + '\n', encoding='utf8')
    os.replace(temp, mods)


def apply(root):
    """Install staged mods (server stopped: run by the launcher). Returns messages."""
    root = Path(root)
    staged = root / WORK / 'staged'
    out = []
    for plan_path in sorted(staged.glob('*/plan.json')):
        stage = plan_path.parent
        plan = json.loads(plan_path.read_text(encoding='utf8'))
        m = MODS.get(plan.get('key'))
        if not m:
            continue
        client = root / 'Resources/Client'
        backup = root / WORK / ('backup-' + time.strftime('%Y%m%d-%H%M%S')) / plan['key']
        # the same mod under another file name is replaced, not doubled
        for path in sorted(client.glob('*.zip')):
            if identify(path)[0] == plan['key']:
                backup.mkdir(parents=True, exist_ok=True)
                shutil.move(str(path), backup / path.name)
        target = client / m['client']
        temp = target.with_suffix('.zip.tmp')
        shutil.copyfile(stage / m['client'], temp)
        os.replace(temp, target)
        update_mods_json(root, target)
        if (stage / 'server').is_dir():
            folder = root / m['server']
            folder.mkdir(parents=True, exist_ok=True)
            for f in (stage / 'server').iterdir():
                if (folder / f.name).exists():
                    backup.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(folder / f.name, backup / f.name)
                shutil.copyfile(f, folder / f.name)
        shutil.rmtree(stage)
        out.append(f"Installed {m['name']} {m['version']}" + (f' (previous copy in {backup})' if backup.exists() else ''))
    return out
