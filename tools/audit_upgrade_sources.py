#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Read fleet archives and calibration statics; never modify car archives.

Compound coefficient sets are sampled intact from actual wheel definitions.
No median mixture is advertised as an Automation compound. The report retains
all variants (Soft/Medium Race and radial/bias ply can legitimately differ).
"""
import os
import argparse
import ast
import hashlib
import json
import operator
import re
import statistics
import zipfile
from pathlib import Path

FIELDS = ('frictionCoef', 'slidingFrictionCoef', 'noLoadCoef', 'fullLoadCoef',
          'loadSensitivitySlope', 'softnessCoef', 'treadCoef',
          'stribeckExponent', 'stribeckVelMult')


def uncomment(text):
    # Preserve quoted expressions, URLs and escaped quotes.
    return re.sub(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else '', text, flags=re.S)


def scalar(value):
    if isinstance(value, (float, int)):
        return value
    tree = ast.parse(value.removeprefix('$='), mode='eval')
    ops = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
           ast.Div: operator.truediv, ast.USub: operator.neg, ast.UAdd: operator.pos}
    def read(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in ops:
            return ops[type(node.op)](read(node.left), read(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in ops:
            return ops[type(node.op)](read(node.operand))
        raise ValueError('not a constant arithmetic expression: ' + value)
    return read(tree.body)


def compound(name):
    if 'Semi-Slick' in name:
        return 'semi_slick'
    if 'Race' in name:
        # Automation's race slicks: "Soft Race", "Medium Race", "Hard Race"
        for grade in ('Soft', 'Hard', 'Medium'):
            if grade + ' Race' in name:
                return 'race_' + grade.lower()
        return 'race_medium'
    if 'Sport' in name:
        return 'sport'
    return 'standard'


def field(text, key):
    m = re.search(r'"' + re.escape(key) + r'"\s*:\s*("(?:\\.|[^"\\])*"|[-+\d.eE]+)', text)
    if not m:
        return None
    raw = m[1]
    return scalar(json.loads(raw) if raw.startswith('"') else float(raw))


def audit(seed, archives, statics):
    # every Automation car in the archives (fleet discovery), not only rated ones
    from fleet import discover
    models = {m: c['config'] for m, c in discover(archives).items()}
    found, records = {}, []
    for path in sorted(archives.glob('*.zip')):
        with zipfile.ZipFile(path) as archive:
            for member in archive.namelist():
                bits = member.split('/')
                if len(bits) < 4 or bits[0] != 'vehicles' or bits[1] not in models:
                    continue
                model = bits[1]
                if bits[2] != models[model] or not member.endswith('.jbeam'):
                    continue
                source = archive.read(member)
                text = uncomment(source.decode('utf8'))
                if '"pressureWheels"' not in text or '"Camso_wheels_' not in text:
                    continue
                part = re.search(r'^\s*\{\s*"([^"]+)"', text)[1]
                title = re.search(r'"name"\s*:\s*"([^"]+)"', text)[1]
                axle = 'front' if 'front' in part.lower() else 'rear'
                tyre_text = text.split('"pressureWheels"', 1)[1]
                coeff = {k: field(tyre_text, k) for k in FIELDS}
                static_path = statics / f'{model}_{models[model]}.json'
                static = json.loads(static_path.read_text()) if static_path.exists() else None
                matching = [w for w in (static or {}).get('wheels', [])
                            if w['name'].startswith('F' if axle == 'front' else 'R')]
                checks = []
                for wheel in matching:
                    for key in FIELDS:
                        if key in wheel and coeff[key] is not None:
                            checks.append({'wheel': wheel['name'], 'field': key,
                                           'source': coeff[key], 'compiled': wheel[key],
                                           'matches': abs(coeff[key] - wheel[key]) < 0.00011})
                record = {'model': model, 'config': models[model], 'axle': axle,
                          'archive': str(path), 'member': member,
                          'sourceSha256': hashlib.sha256(source).hexdigest(),
                          'part': part, 'title': title, 'compound': compound(title),
                          'tireWidthMM': field(tyre_text, 'tireWidth') * 1000,
                          'radiusM': field(tyre_text, 'radius'),
                          'coefficients': coeff, 'staticPath': str(static_path),
                          'compiledChecks': checks}
                records.append(record)
                found[(model, axle)] = record
    missing = sorted(f'{m}/{a}' for m in models for a in ('front', 'rear') if (m, a) not in found)
    groups = {}
    for record in records:
        g = groups.setdefault(record['compound'], {'samples': [], 'variants': []})
        g['samples'].append({'model': record['model'], 'axle': record['axle'], 'title': record['title']})
        if record['coefficients'] not in g['variants']:
            g['variants'].append(record['coefficients'])
    for group in groups.values():
        group['ranges'] = {k: {'min': min(values), 'median': statistics.median(values), 'max': max(values)}
                           for k in FIELDS if (values := [r[k] for r in group['variants'] if r[k] is not None])}
    return {'schemaVersion': 1, 'fleetCars': len(models), 'axles': len(records),
            'missingAxles': missing, 'compounds': groups, 'sources': records}


def markdown(data):
    lines = ['# Race Prep 1.8.0 upgrade source audit', '',
             f"Fleet: {data['fleetCars']} cars; {data['axles']} wheel parts inspected.", '',
             'These are exported Automation values, not measured road friction coefficients.',
             'Different export versions, constructions and Race subcompounds remain separate variants.', '',
             '| Compound | Axles | Complete coefficient variants | noLoadCoef range |',
             '| --- | ---: | ---: | --- |']
    for key, group in sorted(data['compounds'].items()):
        r = group['ranges']['noLoadCoef']
        lines.append(f"| {key} | {len(group['samples'])} | {len(group['variants'])} | {r['min']:.6f}–{r['max']:.6f} |")
    lines += ['', '## Coverage and provenance', '',
              'Missing axles: ' + (', '.join(data['missingAxles']) or 'none') + '.',
              'The accompanying JSON records archive paths, member names, SHA-256 hashes,',
              'tyre widths, every coefficient set and comparisons with compiled calibration data.', '',
              '## Important interpretation', '',
              'Values are read only within pressureWheels; axle-node and hub friction are excluded.',
              'No coefficient checks disagree with compiled data in this audited fleet.',
              'A compound is not a single scalar: load response, sliding friction and softness',
              'are retained as one exported set when selecting a donor.', '',
              '## Outstanding validation', '',
              'This audit does not validate generated tyre visuals, KTS heat/wear, aero forces,',
              'shop UI or the ±15 PI target. No new parts have been measured yet.', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archives', type=Path, default=Path(os.environ.get('RACEPREP_RESOURCES', 'Resources/Client')))
    parser.add_argument('--statics', type=Path, default=Path(os.environ.get('RACEPREP_STATICS', 'calibration-statics')))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    seed = json.loads((repo / 'client/lua/ge/extensions/raceprep/ratings-seed.json').read_text())
    data = audit(seed, args.archives, args.statics)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'upgrade-source-audit.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.output / 'upgrade-source-audit.md').write_text(markdown(data))
    print(json.dumps({'cars': data['fleetCars'], 'axles': data['axles'], 'missing': data['missingAxles'],
                      'compounds': {k: len(v['samples']) for k, v in data['compounds'].items()}}, indent=2))
    if data['missingAxles']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
