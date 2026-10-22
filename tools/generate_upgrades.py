#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Generate every Race Prep upgrade part for every Automation car on the
server, in one step (also run by package.py). Run it after adding a car:

    python3 -I tools/generate_upgrades.py --resources <BeamMP>/Resources/Client

Reads the car zips (never modifies them), removes the previously generated
files and writes: tyre parts, aero kits, brake parts, engine parts and explicitly
tested engine swaps (client/vehicles/<car>/raceprep/) and their catalogues
(upgrade-parts.json, engine-parts.json; swap manifests under client/vehicles).
Same input -> same output.
"""
import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from runtime_paths import TOOLS
HERE = TOOLS
import audit_upgrade_sources  # noqa: E402
import fleet  # noqa: E402
import generate_engine_swaps  # noqa: E402
from engine_swaps.library import generate as generate_swap_library  # noqa: E402
from drivetrain_conversions.library import generate as generate_drivetrain_library  # noqa: E402
import generate_upgrade_aero  # noqa: E402
import generate_upgrade_body  # noqa: E402
import generate_upgrade_brakes  # noqa: E402
import generate_upgrade_engines  # noqa: E402
import generate_upgrade_tyres  # noqa: E402

ROOT = HERE.parent


def clean(output):
    """remove generated files from a previous run (cars may have been removed)"""
    removed = 0
    for folder in (Path(output) / 'vehicles').glob('*/raceprep'):
        for f in folder.glob('rp_*.jbeam'):
            f.unlink()
            removed += 1
        if not any(folder.iterdir()):
            folder.rmdir()
            if not any(folder.parent.iterdir()):
                folder.parent.rmdir()
    return removed


def run(resources, statics, output, update_donors=False, add_donors=(), donors=None, tyre_resources=None):
    """Shared Python/frozen entry point; caller stages output before publishing."""
    resources, statics, output = Path(resources), Path(statics), Path(output)
    cars = fleet.discover(resources)
    print(f'{len(cars)} Automation cars in {resources}', flush=True)
    removed = clean(output)
    print(f'removed {removed} previously generated files', flush=True)
    seed = json.loads((ROOT / 'client/lua/ge/extensions/raceprep/ratings-seed.json').read_text())
    with tempfile.TemporaryDirectory() as tmp:
        audit = audit_upgrade_sources.audit(seed, tyre_resources or resources, statics)
        if audit['missingAxles']:
            print('tyres: no tyre part found for', ', '.join(audit['missingAxles']), flush=True)
        (Path(tmp) / 'audit.json').write_text(json.dumps(audit))
        extra = []
        for folder in add_donors:
            found = audit_upgrade_sources.audit(seed, folder, Path(tmp) / 'no-statics')['sources']
            print(f'donors: {len(found)} tyre sets from {folder}', flush=True)
            extra.extend(found)
        tyre_donors, library = generate_upgrade_tyres.donor_library(audit, extra=extra)
        selected_audit = {**audit, 'sources': [s for s in audit['sources'] if s['model'] in cars], 'fleetCars': len(cars)}
        tyres = generate_upgrade_tyres.generate(selected_audit, output, tyre_donors)
        if update_donors:
            generate_upgrade_tyres.DONOR_LIBRARY.write_text(json.dumps(library, indent=1) + '\n')
            print(f'tyre donor library: {len(library)} Automation tyre sets', flush=True)
    print(f"tyres: {len(tyres['parts'])} parts for {tyres['sourceCars']} cars", flush=True)
    aero = generate_upgrade_aero.generate(seed, statics, output, resources)
    brakes = generate_upgrade_brakes.generate(output, resources)
    parts_path = output / 'lua/ge/extensions/raceprep/upgrade-parts.json'
    data = json.loads(parts_path.read_text())
    data['parts'].update(aero)
    data['parts'].update(brakes)
    # body upgrades (weight reduction) plug into the aero kit slot
    body, _ = generate_upgrade_body.generate(output, {p['model'] for p in aero.values()})
    data['parts'].update(body)
    data['parts'] = dict(sorted(data['parts'].items()))
    data['stocks'] = dict(sorted(data.get('stocks', {}).items()))
    parts_path.write_text(json.dumps(data, indent=2) + '\n')
    print(f'aero: {len(aero)} kits', flush=True)
    print(f'body: {len(body)} parts (holder + Street / Sport / Race per car)', flush=True)
    print(f'brakes: {len(brakes)} parts (Sport / Race, front and rear)', flush=True)
    generate_upgrade_engines.generate(resources, output, statics)
    engines = json.loads((output / 'lua/common/raceprep/engine-parts.json').read_text())
    print(f"engines: parts for {len(engines['models'])} cars", flush=True)
    missing = sorted(set(cars) - set(engines['models']))
    if missing:
        print('no engine parts (unsupported data):', ', '.join(missing), flush=True)
    swaps = generate_engine_swaps.generate(resources, output)
    print(f"engine swaps: {swaps['generated']} tested pairs", flush=True)
    for reason in swaps['skipped']:
        print('engine swap skipped:', reason, flush=True)
    import donor_registry
    registry = donor_registry.load(donors)
    print(f"donors: {registry['counts']}", flush=True)
    with tempfile.TemporaryDirectory(prefix='rp-donors-') as registry_dir:
        engine_manifest, drivetrain_manifest = donor_registry.manifests(registry, registry_dir)
        library = generate_swap_library(resources, output, approved=engine_manifest)
        if donor_registry.drivetrain_set(registry):
            drivetrains = generate_drivetrain_library(resources, output, approved=drivetrain_manifest, strict=True)
            donor_registry.generate_custom_drivetrains(registry, resources, output, registry_dir)
        else:
            # Custom edition without a full FWD / RWD / AWD donor set
            print('drivetrain conversions off: add one FWD, one RWD and one AWD donor to BJRME-donors/custom/drivetrains', flush=True)
            drivetrains = {'parts': 0, 'models': 0}
    print(f"engine conversion library: {library['parts']} compatible pairs for {library['models']} cars", flush=True)
    print(f"drivetrain conversion library: {drivetrains['parts']} compatible layouts for {drivetrains['models']} cars", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--resources', type=Path, default=fleet.RESOURCES, help='folder with the car zips')
    parser.add_argument('--statics', type=Path, default=fleet.STATICS, help='calibration static data (optional)')
    parser.add_argument('--output', type=Path, default=ROOT / 'client', help='add-on client folder')
    parser.add_argument('--update-donors', action='store_true',
                        help='add this fleet\'s tyres to tools/tyre_donors.json (compound donors for future cars)')
    parser.add_argument('--add-donors', type=Path, action='append', default=[],
                        help='also take compound donors from the Automation cars in this folder (read only; '
                             'e.g. Hard Race slicks no server car uses); with --update-donors they are kept')
    parser.add_argument('--donors', type=Path, help='bundled/custom donor root')
    args = parser.parse_args()
    run(args.resources, args.statics, args.output, args.update_donors, args.add_donors, args.donors)


if __name__ == '__main__':
    main()
