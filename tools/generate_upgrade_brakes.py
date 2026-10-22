#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Generate Sport / Race brake parts for every Automation car (Forza style).

Each part is a copy of the car's own front / rear brake part (same slot, same
brake meshes and rotor size) with:
  Sport: brake torque x1.15, pads at least "sport", cooling x1.2
  Race:  brake torque x1.30, pads at least "full-race", cooling x1.5;
         Front / Rear Brake Power (50-150 %) becomes adjustable, because the
         part is a race part (tuning policy), and it is rated at 150 %.
Drum and plain discs become vented discs. Pads are never downgraded
(carbon-ceramic stays). The car mods are only read.
"""
import hashlib
import json
import re
import zipfile
from pathlib import Path

import fleet

LEVELS = {
    'sport': {'torque': 1.15, 'pads': 'sport', 'venting': 1.2, 'title': 'Sport'},
    'race': {'torque': 1.30, 'pads': 'full-race', 'venting': 1.5, 'title': 'Race'},
}
PADS = ['basic', 'premium', 'sport', 'semi-race', 'full-race', 'carbon-ceramic']
RACE_RATED_POWER = 1.5  # Brake Power slider maximum: race parts are rated at their best setting
SLOTS = {'front': 'Camso_brake_F', 'rear': 'Camso_brake_R'}


def block_at(text, start):
    """the {...} object starting at text[start] == '{' (strings respected)"""
    depth, i, quote = 0, start, False
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == '\\':
                i += 1
            elif ch == '"':
                quote = False
        elif ch == '"':
            quote = True
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise ValueError('unterminated part block')


def stock_brakes(model, car):
    """{axle: (part name, part block text, sha256 of its file)} from the car's config folder"""
    prefix = f"vehicles/{model}/{car['config']}/"
    with zipfile.ZipFile(car['archive']) as archive:
        files = {m: archive.read(m) for m in archive.namelist() if m.startswith(prefix) and m.endswith('.jbeam')}
    texts = {m: fleet.uncomment(raw.decode('utf8', 'replace')) for m, raw in files.items()}
    out = {}
    for axle, slot in SLOTS.items():
        defaults = {d for t in texts.values() for d in re.findall(r'\["' + slot + r'"\s*,\s*"([^"]+)"', t)}
        found = []
        for member, text in texts.items():
            for name in defaults:
                m = re.search(r'"' + re.escape(name) + r'"\s*:\s*\{', text)
                if m:
                    found.append((name, block_at(text, m.end() - 1), hashlib.sha256(files[member]).hexdigest()))
        if len(found) == 1:
            out[axle] = found[0]
    return out


def upgraded(block, axle, level, title):
    spec = LEVELS[level]
    text, n = re.subn(r'("brakeTorque"\s*:\s*)"\$=([^"]+)"',
                      lambda m: m[1] + json.dumps(f"$=({m[2].strip()})*{spec['torque']}"), block, count=1)
    if n != 1:
        raise ValueError('brakeTorque expression not found')

    def pads(m):
        current = m[2]
        rank = PADS.index(current) if current in PADS else 0
        return m[1] + json.dumps(PADS[max(rank, PADS.index(spec['pads']))])
    text, n = re.subn(r'("padMaterial"\s*:\s*)"([^"]*)"', pads, text, count=1)
    if n != 1:
        raise ValueError('padMaterial not found')
    text, n = re.subn(r'("brakeVentingCoef"\s*:\s*)([-+\d.eE]+)',
                      lambda m: m[1] + repr(round(float(m[2]) * spec['venting'], 6)), text, count=1)
    if n != 1:
        raise ValueError('brakeVentingCoef not found')
    text = re.sub(r'("brakeType"\s*:\s*)"(drum|disc)"', lambda m: m[1] + '"vented-disc"', text, count=1)
    text = re.sub(r'("information"\s*:\s*\{[^}]*?"name"\s*:\s*)"[^"]*"', lambda m: m[1] + json.dumps(title), text,
                  count=1, flags=re.S)
    return text


def generate(output, resources=fleet.RESOURCES):
    """writes vehicles/<car>/raceprep/rp_brake_*.jbeam; returns catalogue entries"""
    parts = {}
    for model, car in sorted(fleet.discover(resources).items()):
        model_id = hashlib.sha256(model.encode()).hexdigest()[:12]
        for axle, (stock, block, sha) in sorted(stock_brakes(model, car).items()):
            directory = Path(output) / 'vehicles' / model / 'raceprep'
            directory.mkdir(parents=True, exist_ok=True)
            for level, spec in LEVELS.items():
                name = f'rp_brake_{model_id}_{axle}_{level}'
                title = f"{spec['title']} {axle.title()} Brakes" + (' (adjustable)' if level == 'race' else '')
                body = upgraded(block, axle, level, title)
                (directory / (name + '.jbeam')).write_text('{\n' + json.dumps(name) + ': ' + body + '\n}\n')
                parts[name] = {'kind': 'brake', 'name': title, 'model': model, 'axle': axle, 'level': level,
                               'stockPart': stock, 'sourceSha256': sha, 'torqueScale': spec['torque'],
                               'pads': spec['pads'], 'coolingScale': spec['venting'],
                               **({'ratingBrakeScale': RACE_RATED_POWER} if level == 'race' else {})}
    return parts
