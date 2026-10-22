#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Generate additive car-specific tyre parts from a verified fleet source audit.

Only tyre friction fields, tireWidth, tyre mesh lateral scale and (for width
variants) the rim hubWidth, widened by the same offset, and the load
sensitivity, scaled by stock width / new width, change.
Nodes, beams, rim geometry, slots, pressure and stiffness tuning stay intact.
Every non-stock compound copies a complete real coefficient set from its
nearest fleet donor (same construction, then width/radius proximity).
"""
import argparse
import copy
import hashlib
import json
import re
import zipfile
from pathlib import Path
from audit_upgrade_sources import FIELDS, compound as compound_of, field, uncomment

LABELS = {'stock': 'Stock', 'sport': 'Sport', 'semi_slick': 'Semi-slick',
          'race_supersoft': 'Race slick (Super Soft)', 'race_soft': 'Race slick (Soft)',
          'race_medium': 'Race slick (Medium)', 'race_hard': 'Race slick (Hard)'}
OFFSETS = (-20, 0, 20, 40)
# Race slick compound -> Kagoni Tyre Simulation preset (wear, temperature
# window, grip multiplier), set on the car by the add-on. Automation has no
# Super Soft: it uses Soft's coefficients; KTS gives it 1.05x grip against
# Soft's 1.03x, which the rating counts (ratingGripScale).
KTS_PRESETS = {'race_supersoft': 'supersoft', 'race_soft': 'soft', 'race_medium': 'medium', 'race_hard': 'hard'}
DONOR_COMPOUND = {'race_supersoft': 'race_soft'}
RATING_GRIP_SCALE = {'race_supersoft': 1.05 / 1.03}


def donor_for(source, compound, sources):
    compound = DONOR_COMPOUND.get(compound, compound)
    if source.get('compound') == compound:
        return source  # selecting the existing compound preserves this axle's export
    candidates = [s for s in sources if s['compound'] == compound]
    if not candidates:
        raise ValueError('No Automation donor for ' + compound)
    def distance(other):
        same_construction = ('Bias Ply' in source['title']) == ('Bias Ply' in other['title'])
        return (not same_construction, abs(other['tireWidthMM'] - source['tireWidthMM']),
                abs((other.get('radiusM') or 0) - (source.get('radiusM') or 0)),
                other['model'], other['axle'])
    return min(candidates, key=distance)


RACE = ('race_supersoft', 'race_soft', 'race_medium', 'race_hard')
# Automation's grip level also depends on each car's tyre quality, so copying
# whole tyres from other cars does not rank compounds reliably (a high-quality
# Semi-slick out-gripped a low-quality Hard slick). Every compound therefore
# keeps the car's own tyre quality: the car's tyre x Automation's average
# ratio between the two compounds, for the quality-dependent fields; the
# compound's own character (softness, tread, Stribeck, sliding) comes from a
# real tyre of that compound. The car's own compound stays exact.
QUALITY_FIELDS = ('noLoadCoef', 'fullLoadCoef', 'loadSensitivitySlope')


def compound_means(donors):
    rows = {}
    for d in donors:
        rows.setdefault(d['compound'], []).append(d['coefficients'])
    return {c: {f: sum(r[f] for r in rs) / len(rs) for f in QUALITY_FIELDS} for c, rs in sorted(rows.items())}


def compound_donor(source, compound, donors, means):
    """donor-like record for a compound on this car (see above)"""
    own = DONOR_COMPOUND.get(compound, compound)
    character = donor_for(source, compound, donors)
    base = source if source['compound'] in means else donor_for(source, 'race_soft', donors)
    if base is character:
        return character  # the car's own compound: unchanged
    coefficients = dict(character['coefficients'])
    for f in QUALITY_FIELDS:
        coefficients[f] = round(base['coefficients'][f] * means[own][f] / means[base['compound']][f], 9)
    return {**character, 'coefficients': coefficients, 'gripBase': base}


race_donor = compound_donor  # (name used by the 1.8.5 tests)


def replace_fields(text, values):
    # Scope replacements to pressureWheels, excluding hub/axle friction.
    prefix, tail = text.split('"pressureWheels"', 1)
    for name, value in values.items():
        pattern = r'("' + re.escape(name) + r'"\s*:\s*)("(?:\\.|[^"\\])*"|[-+\d.eE]+)'
        tail, count = re.subn(pattern, lambda m: m[1] + json.dumps(value), tail)
        if count != 1:
            raise ValueError(f'Expected exactly one tyre {name}, got {count}')
    return prefix + '"pressureWheels"' + tail


def build(source, donor, compound, offset, raw):
    width = source['tireWidthMM'] + offset
    if width <= 0:
        raise ValueError('Invalid tyre width')
    model_id = hashlib.sha256(source['model'].encode()).hexdigest()[:12]
    # KTS keyword detection sees internal names too. Opaque model IDs prevent
    # a model called '*_sport' from misclassifying its Race slicks as Sport.
    part_name = f"rp_tyre_{model_id}_{source['axle']}_{compound}_{offset:+d}".replace('+', 'p').replace('-', 'm')
    text = uncomment(raw.decode('utf8'))
    # Replace only the top-level name and displayed name, retaining original slot.
    text = re.sub(r'(^\s*\{\s*)"[^"]+"', lambda m: m[1] + json.dumps(part_name), text, count=1)
    actual = source['title'].split('Radial ')[-1].split('Bias Ply ')[-1].split(' Wheels')[0]
    label = LABELS[compound] if compound != 'stock' else 'Stock (' + actual + ')'
    title = f"{width:g} mm {label} {source['axle'].title()} tyres"
    text = re.sub(r'("name"\s*:\s*)"[^"]+"', lambda m: m[1] + json.dumps(title), text, count=1)
    values = {} if compound == 'stock' else donor['coefficients'].copy()
    if any(v is None for v in values.values()):
        raise ValueError('Incomplete Automation donor fields')
    values['tireWidth'] = width / 1000
    if offset:
        # A real width upgrade is a wider tyre on a matching wider rim; a
        # stretched tyre on the stock rim is slower (Tire Rack). The Automation
        # wheel part carries the rim, so its hubWidth widens by the same offset.
        hub = field(text.split('"pressureWheels"', 1)[1], 'hubWidth')
        if not isinstance(hub, (int, float)) or hub <= 0:
            raise ValueError('Wheel part has no rim hubWidth for a width variant')
        values['hubWidth'] = round(hub * 1000 + offset, 6) / 1000
        # BeamNG (and KTS) grip is per tread node, so width alone adds none.
        # A real wider tyre spreads the load: its load sensitivity scales with
        # stock width / new width (owner-approved 2026-10-17).
        slope = values.get('loadSensitivitySlope')
        if slope is None:
            slope = (source.get('coefficients') or {}).get('loadSensitivitySlope')
        if slope is None:
            slope = field(text.split('"pressureWheels"', 1)[1], 'loadSensitivitySlope')
        if not isinstance(slope, (int, float)) or slope <= 0:
            raise ValueError('Tyre has no loadSensitivitySlope for a width variant')
        values['loadSensitivitySlope'] = round(slope * source['tireWidthMM'] / width, 12)
    text = replace_fields(text, values)
    # Exported tyre meshes use vehicle lateral X. Scale tyre meshes only;
    # retain rim scale and centre. The native flexbody then follows wider nodes.
    factor = width / source['tireWidthMM']
    rows = text.splitlines()
    changed_meshes = 0
    for i, row in enumerate(rows):
        if re.search(r'^\s*\["[^"\n]*(?:tyre|tire)', row, flags=re.I):
            rows[i], n = re.subn(r'("scale"\s*:\s*\{\s*"x"\s*:\s*)([-+\d.eE]+)',
                                  lambda m: m[1] + str(float(m[2]) * factor), row)
            changed_meshes += n
    if offset and changed_meshes != 2:
        raise ValueError(f'Unexpected tyre mesh layout for {source["model"]}/{source["axle"]}: {changed_meshes}')
    text = '\n'.join(rows) + '\n'
    return part_name, text, {'name': title, 'kind': 'tyre', 'model': source['model'], 'axle': source['axle'],
                             'compound': compound, 'widthMM': width, 'offsetMM': offset,
                             **({'hubWidthMM': round(values['hubWidth'] * 1000, 6)} if offset else {}),
                             'racingOnly': compound.startswith('race_'),
                             **({'ktsCompound': KTS_PRESETS[compound]} if compound in KTS_PRESETS else {}),
                             **({'ratingGripScale': round(RATING_GRIP_SCALE[compound], 6)} if compound in RATING_GRIP_SCALE else {}),
                             'stockPart': source['part'], 'donorModel': donor['model'],
                             'donorAxle': donor['axle'], 'donorSha256': donor['sourceSha256'],
                             **({'gripBaseModel': donor['gripBase']['model'], 'gripBaseAxle': donor['gripBase']['axle']}
                                if donor.get('gripBase') else {}),
                             'coefficients': source['coefficients'] if compound == 'stock' else values}


from runtime_paths import TOOLS
DONOR_LIBRARY = TOOLS / 'tyre_donors.json'
DONOR_FIELDS = ('model', 'axle', 'compound', 'title', 'tireWidthMM', 'radiusM', 'coefficients', 'sourceSha256')


def donor_library(audit, path=DONOR_LIBRARY, extra=()):
    """Automation tyre sets usable as compound donors: the library kept in the
    repo plus every tyre in this audit (a car built later needs donors even
    if it is alone in the folder), plus `extra` tyre sets of compounds still
    missing. Returns (donors, updated library)."""
    library = json.loads(path.read_text()) if path.exists() else []
    for d in library:  # classification follows the title (race slicks were one compound before 1.8.5)
        d['compound'] = compound_of(d['title'])
    by_key = {(d['model'], d['axle']): d for d in library}
    for s in audit['sources']:
        by_key[(s['model'], s['axle'])] = {k: s.get(k) for k in DONOR_FIELDS}
    # extra folders only fill compounds nobody has yet (Hard Race), so the
    # donors of existing compounds - and their grip - stay the same
    have = {d['compound'] for d in by_key.values()}
    for s in extra:
        if s['compound'] not in have and (s['model'], s['axle']) not in by_key:
            by_key[(s['model'], s['axle'])] = {k: s.get(k) for k in DONOR_FIELDS}
    donors = [by_key[k] for k in sorted(by_key)]
    return donors, donors


def generate(audit, output, donors=None):
    """donors: tyre sets to copy compounds from (default: this audit only)"""
    donors = donors if donors is not None else audit['sources']
    means = compound_means(donors)
    manifest = {'schemaVersion': 1, 'parts': {}, 'sourceCars': audit['fleetCars'], 'stocks': {}}
    for source in audit['sources']:
        manifest['stocks'][source['model'] + '/' + source['axle']] = {
            'part': source['part'], 'widthMM': source['tireWidthMM'], 'compound': source['compound']}
        with zipfile.ZipFile(source['archive']) as archive:
            raw = archive.read(source['member'])
        if hashlib.sha256(raw).hexdigest() != source['sourceSha256']:
            raise ValueError('Fleet source changed since audit: ' + source['member'])
        directory = output / 'vehicles' / source['model'] / 'raceprep'
        directory.mkdir(parents=True, exist_ok=True)
        for compound in LABELS:
            donor = source if compound == 'stock' else compound_donor(source, compound, donors, means)
            for offset in OFFSETS:
                if compound == 'stock' and offset == 0:
                    continue  # original part remains the exact stock option
                name, text, info = build(source, donor, compound, offset, raw)
                (directory / (name + '.jbeam')).write_text(text)
                manifest['parts'][name] = info
    destination = output / 'lua/ge/extensions/raceprep/upgrade-parts.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('audit', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text())
    result = generate(audit, args.output)
    print(f"Generated {len(result['parts'])} tyre parts for {result['sourceCars']} cars in {args.output}")


if __name__ == '__main__':
    main()
