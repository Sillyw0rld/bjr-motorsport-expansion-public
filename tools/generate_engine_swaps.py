#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Regenerate only explicitly tested Automation swap pairs, from installed cars.

Both original cars must be installed: the donor supplies its sound assets.
Archive hashes pin the complete tested source, including supporting engine parts.
No factory archives, factory configs, or unlisted combinations are modified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from runtime_paths import TOOLS
HERE = TOOLS
import fleet
from engine_swaps import catalogue
from engine_swaps.build_prototype import build

RECIPES = HERE / 'engine_swaps/recipes.json'


def generate(resources, output, recipes=RECIPES):
    output = Path(output)
    cars = fleet.discover(resources)
    plans = json.loads(Path(recipes).read_text())
    if plans.get('version') != 1:
        raise ValueError('unsupported engine swap recipe version')
    eligible, skipped, seen = [], [], set()
    for recipe in plans['recipes']:
        recipient, donor = recipe['recipient'], recipe['donor']
        if recipient == donor or recipient in seen:
            raise ValueError('prototype allows one distinct donor per recipient')
        seen.add(recipient)
        if recipient not in cars or donor not in cars:
            skipped.append(f'{recipient} <- {donor}: both source cars must be installed')
            continue
        for role in ('recipient', 'donor'):
            path = Path(cars[recipe[role]]['archive'])
            with path.open('rb') as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            if digest != recipe[role + 'ArchiveSha256']:
                raise ValueError(f'{role} archive changed: {path}; revalidate the swap first')
        eligible.append(recipe)

    archives = {Path(cars[r[role]]['archive']) for r in eligible for role in ('recipient', 'donor')}
    inventory = catalogue.scan(Path(resources), archives=archives)
    prepared = []
    # Validate and build off to the side before replacing generated swap files.
    with tempfile.TemporaryDirectory() as temp:
        for i, recipe in enumerate(eligible):
            selected = []
            for role in ('recipient', 'donor'):
                matches = [r for r in inventory['engines'] if r['model'] == recipe[role]
                           and r['config'] == recipe[role + 'Config']]
                if len(matches) != 1:
                    raise ValueError(f'cannot identify tested {role}: {recipe[role]}: {inventory["errors"]}')
                selected.append(matches[0])
            staging = Path(temp) / str(i)
            manifest = build({'engines': selected}, recipe['recipient'], recipe['donor'], staging)
            manifest['sourceArchiveSha256'] = {role: recipe[role + 'ArchiveSha256']
                                              for role in ('recipient', 'donor')}
            manifest['requiresInstalledDonor'] = recipe['donor']
            prepared.append((recipe, staging, manifest))
        # Bounded cleanup: never remove unrelated generated parts or setups.
        for folder in (output / 'vehicles').glob('*/raceprep'):
            for old in folder.glob('rp_swap_*.jbeam'):
                old.unlink()
            (folder / 'rp_swap_manifest.json').unlink(missing_ok=True)
        for recipe, staging, manifest in prepared:
            folder = output / 'vehicles' / recipe['recipient'] / 'raceprep'
            folder.mkdir(parents=True, exist_ok=True)
            for source in sorted((staging / 'vehicles' / recipe['recipient'] / 'rp_swap').glob('*.jbeam')):
                (folder / f'rp_swap_{recipe["donor"]}_{source.name}').write_bytes(source.read_bytes())
            # Lives under client/vehicles, covered by package.py's generated paths.
            # Test .pc files and private-profile configs are deliberately excluded.
            (folder / 'rp_swap_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return {'generated': len(prepared), 'skipped': skipped}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=fleet.RESOURCES)
    parser.add_argument('--output', type=Path, default=HERE.parent / 'client')
    parser.add_argument('--recipes', type=Path, default=RECIPES)
    parser.add_argument('--library', action='store_true', help='generate the approved donor library (normal builds do this automatically)')
    args = parser.parse_args()
    if args.library:
        from engine_swaps.library import generate as generate_library
        print(json.dumps(generate_library(args.resources,args.output),indent=2))
    else:
        print(json.dumps(generate(args.resources, args.output, args.recipes), indent=2))


if __name__ == '__main__':
    main()
