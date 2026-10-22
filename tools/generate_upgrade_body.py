#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Body upgrades (weight reduction) as real car parts, Forza style.

Automation exports scale every node by $nodeWeightScale ("scalenodeWeight" at
part level), but that variable only exists inside Automation's optional
"Advanced tuning parameters" part, which stock cars leave empty and Race
Prep's aero kits replace. So per car this writes:

  rp_body_<id>_holder      camso_tuning_parameters slot, no aero change: only
                           carries the body slot when no aero kit is fitted
  rp_body_<id>_<stage>     rp_body_<id> slot: defines $nodeWeightScale at the
                           stage's fixed value (hidden, not a slider)

and adds the rp_body_<id> slot to the car's existing aero kits (numbers
untouched). <id> is the aero kits' id: sha256(model)[:12].

Usage: python3 -I tools/generate_upgrade_body.py --output client
"""
import argparse
import hashlib
import json
from pathlib import Path

STAGES = [('street', 0.96, 'Street body: spare wheel and tools removed (-4 % weight)'),
          ('sport', 0.93, 'Sport body: all seats removed (-7 % weight)'),
          ('race', 0.85, 'Race body: stripped race car (-15 % weight)')]
HEADER = ['name', 'type', 'unit', 'category', 'default', 'min', 'max', 'title', 'description']
SLOT_HEADER = ['type', 'default', 'description']


def ident(model):
    return hashlib.sha256(model.encode()).hexdigest()[:12]


def body_slot(model):
    return [f'rp_body_{ident(model)}', '', 'Body: weight reduction']


def parts_for(model):
    i = ident(model)
    out = {f'rp_body_{i}_holder': {
        'information': {'authors': 'Sillyw0rld', 'name': 'Stock aero (holds the Race Prep body slot)'},
        'slotType': 'camso_tuning_parameters',
        'slots': [SLOT_HEADER, body_slot(model)]}}
    manifest = {f'rp_body_{i}_holder': {'kind': 'bodyHolder', 'model': model, 'name': 'Stock aero'}}
    for stage, scale, title in STAGES:
        name = f'rp_body_{i}_{stage}'
        out[name] = {'information': {'authors': 'Sillyw0rld', 'name': title},
                     'slotType': f'rp_body_{i}',
                     'variables': [HEADER, ['$nodeWeightScale', 'range', '', 'Vehicle Advanced Settings', scale, scale, scale,
                                            'Node Weight', 'Race Prep body stage (fixed)', {'hideInUI': True}]]}
        manifest[name] = {'kind': 'body', 'model': model, 'name': title, 'stage': stage, 'scale': scale}
    return out, manifest


def add_slot_to_kits(path, model):
    """the car's aero kits also carry the body slot (kit numbers unchanged)"""
    kits = json.loads(path.read_text())
    changed = False
    for part in kits.values():
        slots = part.get('slots') or [SLOT_HEADER]
        if not any(isinstance(s, list) and s and s[0] == body_slot(model)[0] for s in slots[1:]):
            part['slots'] = slots + [body_slot(model)]
            changed = True
    if changed:
        path.write_text(json.dumps(kits, indent=2) + '\n')
    return changed


def generate(output, models):
    """body parts for every car with aero kits; returns the catalogue entries"""
    catalog, kits_changed = {}, 0
    for model in sorted(models):
        parts, manifest = parts_for(model)
        directory = output / 'vehicles' / model / 'raceprep'
        (directory / 'rp_body_parts.jbeam').write_text(json.dumps(parts, indent=2) + '\n')
        kits_changed += add_slot_to_kits(directory / 'rp_aero_kits.jbeam', model)
        catalog.update(manifest)
    return catalog, kits_changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='client folder (vehicles/, lua/)')
    args = parser.parse_args()
    catalog_path = args.output / 'lua/ge/extensions/raceprep/upgrade-parts.json'
    data = json.loads(catalog_path.read_text())
    models = {p['model'] for p in data['parts'].values() if p.get('kind') == 'aero'}
    body, kits_changed = generate(args.output, models)
    data['parts'].update(body)
    data['parts'] = dict(sorted(data['parts'].items()))
    catalog_path.write_text(json.dumps(data, indent=2) + '\n')
    print(f'Generated body parts for {len(models)} cars; body slot added to {kits_changed} aero kit files')


if __name__ == '__main__':
    main()
