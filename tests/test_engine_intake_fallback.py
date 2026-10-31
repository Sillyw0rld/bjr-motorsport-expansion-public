# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Race Intake must exist even when an Automation export only supplies Stock."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import fleet
import generate_upgrade_engines as engines


class IntakeFallback(unittest.TestCase):
    def test_missing_and_existing_factory_part(self):
        for supplied in (False, True):
            with self.subTest(factory_race_intake=supplied), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                archive = base/'car.zip'
                stock_engine = 'Camso_Engine_test'
                stock_intake = 'Camso_Intake_test'
                race_intake = 'Camso_Intake_race_test'
                pc = {'parts': {'Camso_Engine': stock_engine, stock_intake: stock_intake}}
                parts = {
                    stock_engine: {'information': {'name': 'Stock Engine'}, 'slotType': 'Camso_Engine',
                                   'mainEngine': {'inertia': .2},
                                   'nodes': [['id', 'posX', 'posY', 'posZ'], ['engine0', 0, 0, 0]]},
                    stock_intake: {'information': {'name': 'Stock Intake'}, 'slotType': stock_intake}}
                if supplied:
                    parts[race_intake] = {'information': {'name': 'Race Intake'}, 'slotType': stock_intake}
                with zipfile.ZipFile(archive, 'w') as z:
                    z.writestr('vehicles/test/engine.jbeam', json.dumps(parts))
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                cars = {'test': {'config': 'test', 'archive': str(archive), 'pc': pc}}
                static = {'engines': [{'type': 'camsoEngine', 'maxRPM': 7000}]}
                out = base/'client'
                with patch.object(fleet, 'discover', return_value=cars), patch.object(fleet, 'static', return_value=static):
                    engines.generate(base, out, base/'statics')
                    first = {str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()}
                    engines.generate(base, out, base/'statics')
                    self.assertEqual(first, {str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()})
                self.assertEqual(digest, hashlib.sha256(archive.read_bytes()).hexdigest())
                catalog = json.loads((out/'lua/common/raceprep/engine-parts.json').read_text())['models']['test']
                choices = [(n, p) for n, p in catalog['parts'].items() if p['effect'].get('intake') == 'race']
                self.assertEqual(len(choices), 1)
                name, choice = choices[0]
                self.assertEqual(choice['slot'], stock_intake)
                generated = json.loads((out/'vehicles/test/raceprep/rp_engine_parts.jbeam').read_text())
                if supplied:
                    self.assertEqual(name, race_intake)
                    self.assertNotIn(name, generated)
                else:
                    self.assertTrue(choice['generated'])
                    self.assertEqual(generated[name]['slotType'], stock_intake)
                    self.assertEqual(generated[name]['raceprepEngine'], {'intake': 'race'})

    def test_shipped_engine_catalogues_have_all_existing_race_categories(self):
        catalog = json.loads((ROOT/'client/lua/common/raceprep/engine-parts.json').read_text())
        entries = list(catalog['models'].items())
        entries += [(name, s['engineInfo']) for name, s in catalog.get('swaps', {}).items() if s.get('engineInfo') and not s['engineInfo'].get('native')]
        for model, info in entries:
            for kind, value in [('intake', 'race'), ('ecu', 'race'), ('forged', True), ('flywheel', 'race')]:
                self.assertTrue(any(p['effect'].get(kind) == value for p in info['parts'].values()), (model, kind))
        # Each fallback is a real part in that car's original intake slot.
        for model, info in catalog['models'].items():
            parts = json.loads((ROOT/'client/vehicles'/model/'raceprep/rp_engine_parts.jbeam').read_text())
            for name, p in info['parts'].items():
                if p.get('generated') and p['effect'].get('intake') == 'race':
                    self.assertEqual(parts[name]['slotType'], info['slots']['intake'])
                    self.assertEqual(parts[name]['raceprepEngine'], {'intake': 'race'})


if __name__ == '__main__':
    unittest.main()
