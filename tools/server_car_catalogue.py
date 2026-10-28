# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Discover drivable server mod cars, including non-Automation vehicles.

A model needs its own info, a configuration, and an actual main JBeam part.
Upgrade-only and skin archives must not become spec-car choices. No assets are
extracted or modified; the index contains names, config codes and provenance.
"""
import json
import os
import re
import tempfile
import zipfile
from pathlib import Path

from fleet import loose_json

MAIN = re.compile(rb'''["']slotType["']\s*:\s*["']main["']''')


def _json(archive, name, limit=2 * 1024 * 1024):
    if archive.getinfo(name).file_size > limit:
        raise ValueError('Oversized car metadata')
    return loose_json(archive.read(name).decode('utf-8-sig'))


def _cars(path):
    rows = []
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        for member in sorted(names):
            match = re.fullmatch(r'vehicles/([\w-]+)/info\.json', member)
            if not match:
                continue
            model = match[1]
            prefix = f'vehicles/{model}/'
            try:
                info = _json(archive, member)
                configs = sorted(n[len(prefix):-3] for n in names if n.startswith(prefix)
                                 and '/' not in n[len(prefix):] and n.endswith('.pc'))
                if not isinstance(info, dict) or not configs:
                    continue
                main = False
                for name in sorted(n for n in names if n.startswith(prefix) and n.endswith('.jbeam')):
                    if archive.getinfo(name).file_size > 16 * 1024 * 1024:
                        continue
                    raw = archive.read(name)
                    if MAIN.search(raw):
                        try:
                            data = loose_json(raw.decode('utf-8-sig'))
                        except (ValueError, UnicodeError):
                            continue
                        if isinstance(data, dict) and any(isinstance(p, dict) and p.get('slotType') == 'main'
                                                          for p in data.values()):
                            main = True
                            break
                if not main:
                    continue
                eligible = []
                for config in configs:
                    if not re.fullmatch(r'[\w -]{1,128}', config, flags=re.ASCII):
                        continue
                    pc = _json(archive, prefix + config + '.pc')
                    if not isinstance(pc, dict) or not isinstance(pc.get('parts', pc.get('partsTree')), dict):
                        continue
                    detail_name = prefix + 'info_' + config + '.json'
                    detail = _json(archive, detail_name) if detail_name in names else {}
                    if isinstance(detail, dict) and detail.get('Config Type') != 'Custom':
                        eligible.append((config, detail.get('Config Type') == 'Factory'))
                if not eligible:
                    continue
                codes = [code for code, _ in eligible]
                config = info.get('default_pc')
                if config not in codes:
                    config = next((code for code, factory in eligible if factory), codes[0])
                title = ' '.join(str(v) for v in (info.get('Brand'), info.get('Name', model)) if v)
                rows.append({'model': model, 'name': title, 'config': config})
            except (KeyError, ValueError, UnicodeError, TypeError):
                continue
    return rows


def write_index(client, target):
    client, target = Path(client), Path(target)
    try:
        previous = json.loads(target.read_text())
    except (OSError, ValueError):
        previous = {}
    if not isinstance(previous, dict) or previous.get('schema') != 1:
        previous = {}
    old_archives = previous.get('archives', {})
    if not isinstance(old_archives, dict):
        old_archives = {}
    archives, models = {}, {}
    for path in sorted(p for p in client.iterdir() if p.is_file() and p.suffix.lower() == '.zip'):
        stat = path.stat()
        stamp = [stat.st_size, stat.st_mtime_ns]
        cached = old_archives.get(path.name, {})
        if isinstance(cached, dict) and cached.get('stamp') == stamp and isinstance(cached.get('cars'), list) and cached['cars'] and all(isinstance(c, dict) and isinstance(c.get('model'), str) for c in cached['cars']):
            cars = cached['cars']
        else:
            try:
                cars = _cars(path)
            except (OSError, ValueError, zipfile.BadZipFile):
                cars = []
        archives[path.name] = {'stamp': stamp, 'cars': cars}
        for car in cars:
            models.setdefault(car['model'], {**car, 'archive': path.name})
    value = {'schema': 1, 'models': list(models.values()), 'archives': archives}
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf8', dir=target.parent,
                                         prefix='.car-catalogue-', delete=False) as out:
            temporary = Path(out.name)
            json.dump(value, out, indent=2)
            out.write('\n')
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return len(models)
