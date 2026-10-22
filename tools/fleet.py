#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Automation car discovery for the upgrade generators: any Automation export
in the server's Resources/Client folder, including cars added later.

An Automation car is a vehicle folder with a .pc config whose parts include
"Camso_Engine". Its stock config is the one the ratings seed knows, else the
config whose info file says "Factory", else the first config.

Car data ("static"): the calibration static file when one exists (measured
in game), otherwise derived from the archive: weight from Automation's info
file, aero targets and frontal area from the config's main part, rev limit
from the rev-limiter part. Derived data is marked "derived": True.
"""
import os
import json
import re
import zipfile
from pathlib import Path

from runtime_paths import ROOT
RESOURCES = Path(os.environ.get('RACEPREP_RESOURCES', 'Resources/Client'))
STATICS = Path(os.environ.get('RACEPREP_STATICS', 'calibration-statics'))  # optional measured car data


def uncomment(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'(^|[^:\\])//[^\n]*', r'\1', text)


def loose_json(raw):
    """.pc / info files: JSON with optional trailing commas"""
    return json.loads(re.sub(r',(\s*[}\]])', r'\1', raw))


def _seed_configs():
    path = ROOT / 'client/lua/ge/extensions/raceprep/ratings-seed.json'
    try:
        seed = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return {k.split('/')[0]: k.split('/')[1] for k in seed.get('baselines', {})}


def discover(resources=RESOURCES, archives=None):
    """{model: {config, archive, pc, info}} for every Automation car"""
    seed = _seed_configs()
    cars = {}
    for path in sorted(Path(resources).glob('*.zip') if archives is None else archives):
        try:
            archive = zipfile.ZipFile(path)
        except zipfile.BadZipFile:
            continue  # the server folder holds a few unrelated broken zips
        with archive:
            names = archive.namelist()
            configs = {}
            for member in names:
                bits = member.split('/')
                if len(bits) == 3 and bits[0] == 'vehicles' and bits[2].endswith('.pc'):
                    try:
                        pc = loose_json(archive.read(member).decode('utf8', 'replace'))
                    except ValueError:
                        continue
                    if 'Camso_Engine' in (pc.get('parts') or {}):
                        configs.setdefault(bits[1], {})[bits[2][:-3]] = pc
            for model, by_config in configs.items():
                if model in cars:
                    continue  # first archive wins, like BeamNG's mod order
                infos = {}
                for config in by_config:
                    member = f'vehicles/{model}/info_{config}.json'
                    if member in names:
                        try:
                            infos[config] = loose_json(archive.read(member).decode('utf8', 'replace'))
                        except ValueError:
                            infos[config] = {}
                factory = [c for c in sorted(by_config) if infos.get(c, {}).get('Config Type') == 'Factory']
                config = seed.get(model) if seed.get(model) in by_config else (factory or sorted(by_config))[0]
                cars[model] = {'config': config, 'archive': str(path), 'pc': by_config[config],
                               'info': infos.get(config, {})}
    return cars


def _number(expr):
    """first number of a jbeam value/expression like "$=0.508*(...)" or "$=-15.7+(...)" """
    m = re.search(r'[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?', str(expr))
    return float(m.group(0)) if m else None


def _field(text, key):
    m = re.search(r'"' + re.escape(key) + r'"\s*:\s*("(?:\\.|[^"\\])*"|[-+\d.eE]+)', text)
    if not m:
        return None
    raw = m.group(1)
    return _number(json.loads(raw)) if raw.startswith('"') else float(raw)


def static(model, car, statics=STATICS):
    """measured static data if present, else derived from the archive"""
    path = Path(statics) / f"{model}_{car['config']}.json"
    if path.exists():
        data = json.loads(path.read_text())
        data['derived'] = False
        return data
    with zipfile.ZipFile(car['archive']) as archive:
        texts = {m: uncomment(archive.read(m).decode('utf8', 'replace'))
                 for m in archive.namelist() if m.startswith(f'vehicles/{model}/') and m.endswith('.jbeam')}
    main = next((t for m, t in texts.items() if m.endswith(f"/{car['config']}_main.jbeam")), '')
    if not main:
        main = next((t for t in texts.values() if '"downforceTargetFront"' in t), '')
    aero = {'downforceTargetFront': _field(main, 'downforceTargetFront') or 0.0,
            'downforceTargetRear': _field(main, 'downforceTargetRear') or 0.0,
            'targetSpeedKMH': 200.0, 'vehicleArea': _field(main, 'vehicleArea') or 0.7}
    rev = None
    for text in texts.values():
        m = re.search(r'\["\$revLimitRPM",\s*"range",\s*"[^"]*",\s*"[^"]*",\s*([-\d.eE]+)', text)
        if m:
            rev = float(m.group(1))
            break
    if rev is None:
        for text in texts.values():
            if '"Camso_Engine' in text and '"maxRPM"' in text:
                rev = _field(text, 'revLimiterRPM') or _field(text, 'maxRPM')
                break
    weight = car['info'].get('Weight')
    return {'derived': True, 'mass': float(weight) if weight else None, 'aero': aero,
            'engines': [{'type': 'camsoEngine', 'maxRPM': rev}], 'wheels': [], 'comY': None}


if __name__ == '__main__':
    found = discover()
    print(len(found), 'Automation cars')
    for model, car in sorted(found.items()):
        st = static(model, car)
        print(f"{model:36s} {car['config']:8s} {'derived' if st['derived'] else 'measured'} "
              f"mass {st.get('mass')} revlimit {st['engines'][0].get('maxRPM')}")
