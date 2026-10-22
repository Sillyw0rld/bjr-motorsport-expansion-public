# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Data-only Automation bay parsing, conservative geometry and orientation."""
import copy
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from engine_swaps.catalogue import car_table
from engine_swaps.bay import measure, fit, rotate, verify_frame
from engine_swaps.library import incompatibility


def table(seq):
    return {i: v for i, v in enumerate(seq, 1)}


def design(placement='EngPlace_FrLong_Name'):
    points = table([table([50, -50, 90]), table([50, 50, 80]),
                    table([50, 50, 0]), table([50, -50, 0])])
    body = {key: copy.deepcopy(points) for key in
            ('FrontEngineBounds', 'MidEngineBounds', 'RearEngineBounds')}
    body.update({'UID':'variant', 'Name':'Actual coupe',
                 'EngineTypes':{'FRONT':True, 'MID':True, 'REAR':True},
                 'FrontAxleYPosition':100, 'RearAxleYPosition':-100, 'WheelBase':200})
    yaw = 0 if 'Transverse' in placement else 90 if 'Rear' in placement else -90
    return {'Model':{'EnginePlacement':placement},
            'Trim':{'BodyVariant':body, 'EnginePoint':table([0, 0, 8, yaw])}}


def shape(size, centre=(0, 0, 1)):
    nodes = [{'id':'engine' + str(i), 'pos':[centre[j] + size[j] * (.5 if (i >> j) & 1 else -.5)
                                            for j in range(3)], 'mass':20} for i in range(8)]
    return {'nodes':nodes, 'massKG':160, 'sizeXYZ':list(size),
            'low':[centre[i] - size[i] / 2 for i in range(3)],
            'high':[centre[i] + size[i] / 2 for i in range(3)]}


def car(size=(.3, .3, .3), placement='EngPlace_FrLong_Name', centre=(0, 0, 1)):
    return {'engineGeometry':shape(size, centre), 'engineBay':measure(design(placement)),
            'enginePart':'test', 'fuel':'Gasoline', 'engineDevice':'camsoEngine'}


class Parser(unittest.TestCase):
    def test_legacy_nested_arrays_and_raw_string_bytes(self):
        raw = b'do local _={Trim={FrontEngineBounds={{50,100,75},{50,200,60}},Data="\\1T\\0\\255\xff"},Family={Name="Caf\xc3\xa9"}};error("never run");return _ end'
        result = car_table(raw)
        self.assertEqual(result['Trim']['FrontEngineBounds'][2][3], 60)
        self.assertEqual(result['Family']['Name'], 'Caf\u00e9')
        self.assertEqual(result['Trim']['Data'][:4], '\x01T\x00\xff')

    def test_literal_rejects_expressions(self):
        for expression in ('os.execute("x")', 'function() return 1 end', '1+2', 'other', '1e999'):
            with self.subTest(expression=expression), self.assertRaises(ValueError):
                car_table(('do local _={a=' + expression + '} return _ end').encode())
        for text in ('do local _={a={1,2}', 'do local _={a=1,a=2}', 'do local _={a="\\999"}'):
            with self.assertRaises(ValueError):
                car_table(text.encode())

    def test_binary_and_legacy_arrays_match(self):
        def string(s):
            b = s.encode()
            return b'S' + struct.pack('<I', len(b)) + b
        def literal(v):
            if isinstance(v, dict):
                return b'T' + struct.pack('<II', 0, len(v)) + b''.join(literal(k) + literal(x) for k, x in v.items())
            if isinstance(v, str):
                return string(v)
            return b'N' + struct.pack('<d', v)
        expected = {'Trim':{'EnginePoint':{1:0, 2:123, 3:8, 4:-90}}}
        binary = b'\x01' + literal(expected)
        legacy = b'do local _={Trim={EnginePoint={0,123,8,-90}}} return _ end'
        self.assertEqual(car_table(binary), car_table(legacy))


class Bays(unittest.TestCase):
    def test_uses_variant_cm_half_width_and_lowest_roof(self):
        data = design()
        data['Model']['BodyFamily'] = {'FrontEngineBounds':'wrong roomier saloon'}
        b = measure(data)
        self.assertTrue(b['available'])
        self.assertEqual(b['source'], 'Trim.BodyVariant.FrontEngineBounds')
        self.assertEqual(b['sizeXYZ'], [1, 1, .8])
        self.assertEqual(b['usableSizeXYZ'], [.96, .96, .76])
        self.assertEqual(b['roofRangeM'], [.8, .9])

    def test_selects_active_bay(self):
        for placement, key in [('EngPlace_FrTransverse_Name', 'FrontEngineBounds'),
                               ('EngPlace_MidLong_Name', 'MidEngineBounds'),
                               ('EngPlace_RearLong_Name', 'RearEngineBounds')]:
            b = measure(design(placement))
            self.assertTrue(b['available'])
            self.assertTrue(b['source'].endswith(key))

    def test_invalid_data_fails_closed(self):
        for mutate in [lambda d:d['Trim'].pop('BodyVariant'),
                       lambda d:d['Trim']['BodyVariant'].pop('FrontEngineBounds'),
                       lambda d:d['Trim']['BodyVariant']['FrontEngineBounds'][1].update({1:float('nan')}),
                       lambda d:d['Trim']['BodyVariant']['FrontEngineBounds'][3].update({2:20}),
                       lambda d:d['Trim']['EnginePoint'].update({4:45}),
                       lambda d:d['Trim']['BodyVariant']['EngineTypes'].update({'FRONT':False})]:
            data = design()
            mutate(data)
            self.assertFalse(measure(data)['available'])

    def test_exported_axles_confirm_scale_and_y_reflection(self):
        data = design()
        f = '["mesh", ["wheel_FL", "axf_L"], [], {"pos":{"x":0.7,"y":-1,"z":0.4}}]'
        r = '["mesh", ["wheel_RL", "axr_L"], [], {"pos":{"x":0.7,"y":1,"z":0.4}}]'
        self.assertTrue(verify_frame(measure(data), data, f, r)['frameCheck']['passed'])
        self.assertFalse(verify_frame(measure(data), data, f.replace('"y":-1', '"y":-100'), r)['available'])
        self.assertFalse(verify_frame(measure(data), data, '', r)['available'])

    def test_larger_than_original_allowed_inside_bay(self):
        r, d = car(), car((.6, .65, .4))
        result = fit(r, d)
        self.assertTrue(result['accepted'])
        self.assertEqual(result['method'], 'automation-bay-envelope')
        self.assertEqual(result['nodes'][0]['mass'], d['engineGeometry']['nodes'][0]['mass'])

    def test_oversize_clearance_and_original_mount_position(self):
        for size in [(1, .3, .3), (.3, 1, .3), (.3, .3, .8)]:
            self.assertFalse(fit(car(), car(size))['accepted'])
        r = car(centre=(.3, 0, 1))
        self.assertFalse(fit(r, car((.6, .3, .3)))['accepted'])

    def test_orientation_rotates_real_nodes_about_centre(self):
        r, d = car(placement='EngPlace_FrTransverse_Name'), car((.25, .7, .4))
        p = fit(r, d)
        self.assertTrue(p['accepted'])
        self.assertEqual(p['rotationDegrees'], -90)
        for actual, expected in zip(p['donorOrientedSizeXYZ'], [.7, .25, .4]):
            self.assertAlmostEqual(actual, expected)
        self.assertEqual(rotate([1, 2, 3], 180), [-1, -2, 3])
        with self.assertRaises(ValueError):
            rotate([1, 2, 3], 45)

    def test_missing_or_unverified_metadata_retains_old_envelope(self):
        r, d = car(), car((.6, .6, .4))
        r['engineBay'] = {'available':False, 'reason':'unknown format'}
        p = fit(r, d)
        self.assertFalse(p['accepted'])
        self.assertEqual(p['method'], 'stock-block-fallback')
        self.assertTrue(fit(r, car((.2, .2, .2)))['accepted'])
        r = car()
        r['engineBay']['sizeXYZ'] = [.1, .1, .1]
        self.assertEqual(fit(r, d)['method'], 'stock-block-fallback')

    def test_fuel_and_runtime_checks_still_apply(self):
        r, d = car(), car((.4, .4, .4))
        d['enginePart'] = 'donor'
        self.assertIsNone(incompatibility(r, d))
        d['fuel'] = 'Ethanol'
        self.assertTrue(incompatibility(r, d).startswith('Fuel conversion unavailable:'))
        d['fuel'] = 'Gasoline'
        r['engineDevice'] = 'combustionEngine'
        self.assertIn('runtime unavailable', incompatibility(r, d))

    def test_inconsistent_geometry_cannot_bypass_builder(self):
        d = car()
        d['engineGeometry']['sizeXYZ'] = [.1, .1, .1]
        self.assertFalse(fit(car(), d)['accepted'])


if __name__ == '__main__':
    unittest.main()
