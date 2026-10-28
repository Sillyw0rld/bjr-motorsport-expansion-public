#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Export native model/display/config names only; no BeamNG assets are copied."""
import argparse
import json
import zipfile
from pathlib import Path

from fleet import loose_json

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vehicles', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'server/RacePrep/series-native-cars.json')
    args = parser.parse_args()
    native = json.loads((ROOT / 'client/lua/ge/extensions/raceprep/native-parts.json').read_text())
    models = []
    for model in sorted(native['nativeBodies']['models']):
        archive = args.vehicles / (model + '.zip')
        if not archive.is_file():
            continue
        with zipfile.ZipFile(archive) as source:
            info = loose_json(source.read(f'vehicles/{model}/info.json').decode('utf8'))
            config = info.get('default_pc')
            if not config or f'vehicles/{model}/{config}.pc' not in source.namelist():
                continue
            models.append({'model': model, 'name': ' '.join(filter(None, [info.get('Brand'), info.get('Name', model)])),
                           'config': config})
    args.output.write_text(json.dumps({'schema': 1, 'source': 'BeamNG native model and default factory configuration names; base game required on clients',
                                       'models': models}, indent=2) + '\n')


if __name__ == '__main__':
    main()
