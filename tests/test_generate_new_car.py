# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""A car the generators have never seen (no ratings, no calibration data)
gets every upgrade, and generation is deterministic.

The Neonna GT export is copied under a new model id (rp_newcar) into a
temporary Resources folder; tools/generate_upgrades.py runs on it with no
calibration statics. Skipped when the server's car zips are not present.
"""
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import fleet  # noqa: E402

SOURCE = 'neonna_gt'
NEW = 'rp_newcar'


def tree_hash(folder):
    h = hashlib.sha256()
    for f in sorted(p for p in Path(folder).rglob('*') if p.is_file()):
        h.update(str(f.relative_to(folder)).encode())
        h.update(f.read_bytes())
    return h.hexdigest()


@unittest.skipUnless(fleet.RESOURCES.exists(), 'server car zips not available')
class NewCar(unittest.TestCase):
    def test_unknown_car_gets_every_upgrade(self):
        cars = fleet.discover()
        self.assertIn(SOURCE, cars)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            resources = tmp / 'Client'
            resources.mkdir()
            with zipfile.ZipFile(cars[SOURCE]['archive']) as src, \
                    zipfile.ZipFile(resources / 'newcar.zip', 'w', zipfile.ZIP_DEFLATED) as dst:
                for member in src.namelist():
                    if member.startswith(f'vehicles/{SOURCE}/'):
                        dst.writestr(member.replace(f'vehicles/{SOURCE}/', f'vehicles/{NEW}/', 1), src.read(member))
            out = tmp / 'client'
            (out / 'lua/ge/extensions/raceprep').mkdir(parents=True)
            (out / 'lua/common/raceprep').mkdir(parents=True)
            cmd = [sys.executable, '-I', str(ROOT / 'tools/generate_upgrades.py'), '--resources', str(resources),
                   '--statics', str(tmp / 'no-statics'), '--output', str(out)]
            first = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            folder = out / 'vehicles' / NEW / 'raceprep'
            tyres = sorted(folder.glob('rp_tyre_*.jbeam'))
            self.assertEqual(len(tyres), 54, 'stock+6 compounds x 4 widths x 2 axles, minus the 2 original parts')
            brakes = sorted(folder.glob('rp_brake_*.jbeam'))
            self.assertEqual(len(brakes), 4, 'Sport and Race brakes, front and rear')
            race = (folder / [b.name for b in brakes if b.name.endswith('_front_race.jbeam')][0]).read_text()
            self.assertIn('*1.3"', race, 'race brake torque x1.30')
            self.assertIn('"padMaterial":"full-race"', race.replace(' ', ''))
            self.assertIn('$BrakePowerFront', race, 'race brakes keep the Brake Power setting')
            self.assertIn('"slotType" : "Camso_brake_F"', race)
            kits = json.loads((folder / 'rp_aero_kits.jbeam').read_text())
            self.assertEqual(len(kits), 3)
            engine = json.loads((folder / 'rp_engine_parts.jbeam').read_text())
            self.assertTrue(any(k.endswith('_hub') for k in engine))
            self.assertTrue(any('_induction_turbo_small_' in k for k in engine), 'NA engine gets turbo choices')
            catalog = json.loads((out / 'lua/common/raceprep/engine-parts.json').read_text())
            info = catalog['models'][NEW]
            self.assertEqual(info['stockRevLimit'], 7700, 'rev limit derived from the rev-limiter part')
            self.assertFalse(info['stockForcedInduction'])
            parts = json.loads((out / 'lua/ge/extensions/raceprep/upgrade-parts.json').read_text())['parts']
            aero = [p for p in parts.values() if p.get('kind') == 'aero' and p.get('model') == NEW]
            race = next(p for p in aero if p['kit'] == 'race')
            self.assertAlmostEqual(race['maxDownforceKG'], (961 + 40) * 0.60, places=3,
                                   msg='race kit = 60 % of the export weight (+40 kg fuel reference)')
            digest = tree_hash(out)
            second = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertEqual(tree_hash(out), digest, 'same input -> same output')


if __name__ == '__main__':
    unittest.main()
