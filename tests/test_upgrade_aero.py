# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
import json
import sys
import tempfile
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import generate_upgrade_aero as aero


class Aero(unittest.TestCase):
    def test_parts_caps_and_old_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            st = {'mass': 1000, 'comY': 0, 'wheels': [
                {'name': 'FL', 'y': -1}, {'name': 'FR', 'y': -1},
                {'name': 'RL', 'y': 1}, {'name': 'RR', 'y': 1}],
                'aero': {'downforceTargetFront': 10*aero.G, 'downforceTargetRear': 20*aero.G,
                         'targetSpeedKMH': 200, 'vehicleArea': .5}}
            (root/'car_config.json').write_text(json.dumps(st))
            result = aero.generate({}, root, root/'out', cars={'car': {'config': 'config', 'archive': '', 'pc': {}, 'info': {}}})
            parts = json.loads((root/'out/vehicles/car/raceprep/rp_aero_kits.jbeam').read_text())
            self.assertEqual(len(parts), 3)
            for name, info in result.items():
                share, ld = aero.KITS[info['kit']]
                self.assertAlmostEqual(info['maxDownforceKG'], 1040*share)
                self.assertAlmostEqual(info['ratedFrontN']+info['ratedRearN'], info['maxDownforceKG']*aero.G)
                self.assertEqual(info['liftDrag'], ld)
                part = parts[name]
                self.assertEqual(part['slotType'], 'camso_tuning_parameters')
                variables = {v[0]: v for v in part['variables'][1:]}
                for key in ('$downforceAdjust_F', '$downforceAdjust_R', '$constantDownforce_F', '$constantDownforce_R'):
                    self.assertEqual(variables[key][4:7], [0, 0, 0])
                    self.assertTrue(variables[key][9]['hideInUI'])
                self.assertEqual(variables['$rpAeroFront'][5], 0)
                self.assertEqual(variables['$rpAeroRear'][5], 0)
                self.assertAlmostEqual(variables['$rpAeroFront'][6], info['maxDownforceLB'])
                self.assertIn('ratedCdA', part['raceprepAero'])
                self.assertEqual(part['raceprepAero']['baseCdA'], .5)
                self.assertAlmostEqual(part['raceprepAero']['baseFrontN'], 10*aero.G)
                self.assertAlmostEqual(part['raceprepAero']['baseRearN'], 20*aero.G)
                self.assertNotIn('controller', part)  # uses original cefaero exactly once
            st['aero']['downforceTargetFront'] = 500*aero.G
            st['aero']['downforceTargetRear'] = 500*aero.G
            (root/'car_config.json').write_text(json.dumps(st))
            for info in aero.generate({}, root, root/'out', cars={'car': {'config': 'config', 'archive': '', 'pc': {}, 'info': {}}}).values():
                self.assertAlmostEqual(info['maxDownforceKG'], 1000)
                self.assertAlmostEqual(info['extraDragN'], 0)
                self.assertAlmostEqual(info['ratedFrontN'], 500*aero.G)
                self.assertAlmostEqual(info['ratedRearN'], 500*aero.G)


if __name__ == '__main__':
    unittest.main()
