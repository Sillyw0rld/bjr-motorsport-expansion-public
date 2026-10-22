#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Add car-specific aero tuning parts using Automation's existing cefaero.

No second force controller: JBeam produces bounded targets and CdA for the
native controller. Old constant/downforce +/-2000kg controls are locked.
"""
import os
import argparse
import hashlib
import json
from pathlib import Path

LB = 2.20462262185
G = 9.80665
RHO = 1.2041
V = 200 / 3.6
KITS = {'street': (.08, 2), 'sport': (.20, 2.5), 'race': (.60, 3)}
HEADER = ['name', 'type', 'unit', 'category', 'default', 'min', 'max', 'title', 'description']


def generate(seed, statics, output, resources=None, cars=None):
    """cars: {model: {config, archive, pc, info}}; default: every Automation car
    in the resources folder (fleet discovery)"""
    from fleet import RESOURCES, discover, static
    manifest = {}
    if cars is None:
        cars = discover(resources or RESOURCES)
    for model in sorted(cars):
        st = static(model, cars[model], statics)
        if not st.get('mass'):
            print('aero: no weight for', model, '- skipped')
            continue
        aero = st['aero']
        # Export targets are signed newtons; positive means downforce.
        speed_factor = (200 / aero['targetSpeedKMH']) ** 2
        base_f = aero['downforceTargetFront'] * speed_factor / G
        base_r = aero['downforceTargetRear'] * speed_factor / G
        mass = st['mass'] + 40  # same fuel reference as the rating model
        if st.get('wheels') and st.get('comY') is not None:
            f_y = sum(w['y'] for w in st['wheels'] if w['name'].startswith('F')) / 2
            r_y = sum(w['y'] for w in st['wheels'] if w['name'].startswith('R')) / 2
            split = (r_y - st['comY']) / (r_y - f_y)
        else:
            split = 0.45  # default slider split for cars without measured data
        parts = {}
        ident = hashlib.sha256(model.encode()).hexdigest()[:12]
        for kit, (share, ld) in KITS.items():
            ceiling = max(base_f + base_r, mass * share)
            extra = max(0, ceiling - base_f - base_r)
            requested_f, requested_r = ceiling * split, ceiling * (1 - split)
            df, dr = max(0, requested_f - base_f), max(0, requested_r - base_r)
            ratio = min(1, extra / max(df + dr, 1e-9))
            rated_f, rated_r = base_f + df * ratio, base_r + dr * ratio
            rated_cda = aero['vehicleArea'] + extra * G / (ld * .5 * RHO * V ** 2)
            raw_f = f'max(0, ($rpAeroFront or {requested_f*LB}) / {LB} - ({base_f}))'
            raw_r = f'max(0, ($rpAeroRear or {requested_r*LB}) / {LB} - ({base_r}))'
            scale = f'min(1, {extra} / max(0.000001, ({raw_f}) + ({raw_r})))'
            effective_f = f'({base_f} + ({raw_f}) * ({scale}))'
            effective_r = f'({base_r} + ({raw_r}) * ({scale}))'
            area = f"{aero['vehicleArea']} + (({raw_f}) + ({raw_r})) * ({scale}) * {G/(ld*.5*RHO*V**2)}"
            name = f'rp_aero_{ident}_{kit}'
            title = f'{kit.title()} aero: {ceiling*LB:.0f} lbs at 200 km/h, +{extra*G/ld:.0f} N drag max'
            variables = [HEADER,
                         ['$rpAeroFront', 'range', 'lbs', 'Car Aerodynamics', requested_f*LB, 0, ceiling*LB,
                          'Front downforce at 200 km/h', 'Combined front/rear values share the kit maximum; stock aero is the minimum.', {'stepDis': 1}],
                         ['$rpAeroRear', 'range', 'lbs', 'Car Aerodynamics', requested_r*LB, 0, ceiling*LB,
                          'Rear downforce at 200 km/h', 'PI always uses this kit at maximum, regardless of the sliders.', {'stepDis': 1}]]
            for old, default in [('$downforceAdjust_F', 0), ('$downforceAdjust_R', 0),
                                 ('$constantDownforce_F', 0), ('$constantDownforce_R', 0),
                                 ('$frontalAreaAdjust', 1), ('$downforceTargetSpeed', 200)]:
                variables.append([old, 'range', '', 'Car Aerodynamics', default, default, default,
                                  'Locked by aero kit', 'Native aero kit replaces this control.', {'hideInUI': True}])
            parts[name] = {'information': {'authors': 'Sillyw0rld', 'name': title},
                           'slotType': 'camso_tuning_parameters', 'variables': variables,
                           # body upgrades (weight reduction) plug in under the kit
                           'slots': [['type', 'default', 'description'], [f'rp_body_{ident}', '', 'Body: weight reduction']],
                           'downforceModel': {'downforceTargetFront': '$=' + effective_f + '*' + str(G),
                                              'downforceTargetRear': '$=' + effective_r + '*' + str(G),
                                              'targetSpeedKMH': 200, 'constantForceFront': 0, 'constantForceRear': 0},
                           'dragModel': {'vehicleArea': '$=' + area},
                           # base*: the car's stock aero, so the rating can treat the kit's
                           # EXTRA drag on its own (formula v6: measured x1.30 of rated)
                           'raceprepAero': {'kit': kit, 'ratedFrontN': rated_f*G, 'ratedRearN': rated_r*G,
                                            'ratedCdA': rated_cda, 'liftDrag': ld,
                                            'baseFrontN': base_f*G, 'baseRearN': base_r*G, 'baseCdA': aero['vehicleArea']}}
            manifest[name] = {'kind': 'aero', 'model': model, 'name': title, 'kit': kit,
                              'maxDownforceLB': ceiling*LB, 'maxDownforceKG': ceiling,
                              'extraDragN': extra*G/ld, 'extraCdA': rated_cda-aero['vehicleArea'],
                              'liftDrag': ld, 'stockFrontKG': base_f, 'stockRearKG': base_r,
                              'ratedFrontN': rated_f*G, 'ratedRearN': rated_r*G}
        directory = output / 'vehicles' / model / 'raceprep'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'rp_aero_kits.jbeam').write_text(json.dumps(parts, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--statics', type=Path, default=Path(os.environ.get('RACEPREP_STATICS', 'calibration-statics')))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resources', type=Path, default=None)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    seed = json.loads((root / 'client/lua/ge/extensions/raceprep/ratings-seed.json').read_text())
    manifest = generate(seed, args.statics, args.output, args.resources)
    path = args.output / 'lua/ge/extensions/raceprep/upgrade-parts.json'
    data = json.loads(path.read_text()) if path.exists() else {'schemaVersion': 1, 'parts': {}}
    data['parts'].update(manifest)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n')
    print('Generated', len(manifest), 'aero parts')


if __name__ == '__main__':
    main()
