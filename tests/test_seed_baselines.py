# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Every seeded factory config must be found by model/config (seed.baselines).

Without a baseline the vehicle list compiles the config's jbeam to find its
rating (40-80 ms a frame): 2.10.0.137 shipped 740 native estimates without
baselines and the game ran at ~15 fps (owner 2026-10-17)."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
for rel in ('client/lua/ge/extensions/raceprep/ratings-seed.json', 'server/RacePrep/ratings-seed.json'):
    seed = json.loads((ROOT / rel).read_text())
    base = seed.get('baselines') or {}
    missing = [k for k, e in seed['entries'].items()
               if (e.get('estimate') or (e.get('native') and e.get('source') == 'measured'))
               and base.get(e['model'] + '/' + e['config']) != k]
    assert not missing, f'{rel}: {len(missing)} factory entries without a baseline, e.g. {missing[:3]}'
    assert all(k in seed['entries'] for k in base.values()), rel + ': baseline points to a missing entry'
print('PASS: every seeded factory config has a baseline (no jbeam compile in the vehicle list)')
