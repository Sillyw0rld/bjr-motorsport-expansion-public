# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Offline provenance and mutation-scope checks for generated Automation tyres."""
import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import audit_upgrade_sources as audit
import generate_upgrade_tyres as tyres


class Sources(unittest.TestCase):
    def test_comments_and_arithmetic(self):
        self.assertEqual(audit.uncomment('{"url":"a//b",/* comment */"x":1}// tail'), '{"url":"a//b","x":1}')
        self.assertAlmostEqual(audit.scalar('$=0.000158*0.9'), .0001422)
        with self.assertRaises(ValueError):
            audit.scalar('__import__("os").system("false")')

    def test_clone_scope(self):
        source = {'model': 'fixture', 'axle': 'front', 'part': 'Camso_wheels_front_fixture',
                  'title': 'Car 200/50/18 Radial Sport Steel Front Wheels', 'compound': 'sport',
                  'tireWidthMM': 200, 'coefficients': {k: 1 for k in audit.FIELDS}, 'sourceSha256': 'test'}
        raw = ('{"Camso_wheels_front_fixture":{"information":{"name":"Original"},'
               '"slotType":"Camso_wheels_front",\n"flexbodies":[\n'
               '["fixture_tyre",[],[],{"scale":{"x":1,"y":1,"z":1}}],\n'
               '["fixture_tyre",[],[],{"scale":{"x":1,"y":1,"z":1}}],\n'
               '["fixture_rim",[],[],{"scale":{"x":1,"y":1,"z":1}}]],\n'
               '"nodes":[{"frictionCoef":0.5}],"pressureWheels":[{"hubWidth":0.2},{"tireWidth":0.2},'
               + ','.join('{"' + k + '":0.7}' for k in audit.FIELDS) + ']}}').encode()
        name, text, info = tyres.build(source, source, 'sport', 40, raw)
        part = json.loads(text)[name]
        self.assertEqual(part['nodes'], [{'frictionCoef': .5}])
        self.assertEqual(part['slotType'], 'Camso_wheels_front')
        self.assertEqual(part['flexbodies'][0][3]['scale']['x'], 1.2)
        self.assertEqual(part['flexbodies'][2][3]['scale']['x'], 1)
        self.assertEqual(part['pressureWheels'][1]['tireWidth'], .24)
        self.assertEqual(part['pressureWheels'][0]['hubWidth'], .24)  # matching wider rim
        self.assertEqual(info['hubWidthMM'], 240)
        self.assertEqual(info['widthMM'], 240)
        self.assertFalse(info['racingOnly'])
        hard = tyres.build(source, source, 'race_hard', 0, raw)[2]
        self.assertTrue(hard['racingOnly'])
        self.assertEqual(hard['ktsCompound'], 'hard')
        self.assertIn('Race slick (Hard)', hard['name'])
        supersoft = tyres.build(source, source, 'race_supersoft', 0, raw)[2]
        self.assertEqual(supersoft['ktsCompound'], 'supersoft')
        self.assertAlmostEqual(supersoft['ratingGripScale'], 1.05 / 1.03, places=6)

    def test_automation_race_compound_names(self):
        self.assertEqual(audit.compound('GT 225/55/17 Radial Medium Race Alloy Rear Wheels'), 'race_medium')
        self.assertEqual(audit.compound('Osti 265/30/20 Radial Hard Race Alloy Front Wheels'), 'race_hard')
        self.assertEqual(audit.compound('GT RR 235/45/19 Bias Ply Soft Race Alloy Front Wheels'), 'race_soft')
        self.assertEqual(audit.compound('Lory 245/45/18 Radial Semi-Slick Alloy Front Wheels'), 'semi_slick')

    def test_race_compounds_share_the_car_base(self):
        def tyre(model, compound, no_load, softness, width=250):
            keys = {'noLoadCoef': no_load, 'fullLoadCoef': no_load / 10, 'loadSensitivitySlope': .0001,
                    'softnessCoef': softness}
            return {'model': model, 'axle': 'front', 'compound': compound, 'title': 'Radial', 'tireWidthMM': width,
                    'radiusM': .3, 'coefficients': keys, 'sourceSha256': model}
        # a high-quality Medium and a low-quality Soft: per-car donors would rank them wrongly
        # (fleet averages: Soft 2.1 > Medium 1.8 > Hard 1.6, as in Automation's data)
        donors = [tyre('lowsoft', 'race_soft', 1.8, 1.0), tyre('highsoft', 'race_soft', 2.4, 1.0, 320),
                  tyre('highmedium', 'race_medium', 2.0, .94), tyre('lowmedium', 'race_medium', 1.6, .94, 320),
                  tyre('hard', 'race_hard', 1.6, .8)]
        means = tyres.compound_means(donors)
        source = tyre('car', 'sport', 1.5, .6)
        grip = {c: tyres.race_donor(source, c, donors, means)['coefficients'] for c in tyres.RACE}
        self.assertLess(grip['race_hard']['noLoadCoef'], grip['race_medium']['noLoadCoef'])
        self.assertLess(grip['race_medium']['noLoadCoef'], grip['race_soft']['noLoadCoef'])
        self.assertEqual(grip['race_supersoft'], grip['race_soft'])
        self.assertEqual(grip['race_medium']['softnessCoef'], .94, 'compound character from a real Medium')
        own = tyre('car', 'race_medium', 1.9, .94)
        self.assertIs(tyres.race_donor(own, 'race_medium', donors, means), own, "a car's own slick stays exact")

    def test_brake_pads_never_downgraded(self):
        import generate_upgrade_brakes as brakes
        block = ('{"information":{"authors":"BeamNG","name":"X Front Brakes"},"slotType":"Camso_brake_F",'
                 '"pressureWheels":[{"brakeTorque":"$=1000*$BrakePowerFront*0.8"},{"brakeType":"drum"},'
                 '{"padMaterial":"carbon-ceramic"},{"brakeVentingCoef":1.1}]}')
        sport = brakes.upgraded(block, 'front', 'sport', 'Sport Front Brakes')
        self.assertIn('"carbon-ceramic"', sport)
        self.assertIn('"$=(1000*$BrakePowerFront*0.8)*1.15"', sport)
        self.assertIn('"vented-disc"', sport)
        self.assertIn('"name":"Sport Front Brakes"', sport)
        basic = brakes.upgraded(block.replace('carbon-ceramic', 'basic'), 'front', 'race', 'Race Front Brakes')
        self.assertIn('"full-race"', basic)
        self.assertIn('1.65', basic)
        self.assertEqual(brakes.block_at('x {"a":"}",{"b":1}} y', 2), '{"a":"}",{"b":1}}')

    def test_stock_coefficients_unchanged(self):
        raw = 'prefix "pressureWheels":[{"tireWidth":.20},{"noLoadCoef":1.5}]'
        text = tyres.replace_fields(raw, {'tireWidth': .24})
        self.assertIn('"noLoadCoef":1.5', text)
        self.assertTrue(text.startswith('prefix '))

    def test_donor_construction_then_size(self):
        source = {'title': 'Bias Ply', 'tireWidthMM': 200}
        donors = [{'compound': 'sport', 'title': 'Radial', 'tireWidthMM': 200, 'model': 'a', 'axle': 'front'},
                  {'compound': 'sport', 'title': 'Bias Ply', 'tireWidthMM': 220, 'model': 'b', 'axle': 'rear'}]
        self.assertEqual(tyres.donor_for(source, 'sport', donors)['model'], 'b')
        with self.assertRaises(ValueError):
            tyres.donor_for(source, 'missing', donors)


if __name__ == '__main__':
    unittest.main()
