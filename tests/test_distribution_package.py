# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Public release contents, default donors, custom isolation and executable mode."""
import contextlib
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build_release


class Release(unittest.TestCase):
    def test_public_requires_native_build(self):
        with self.assertRaisesRegex(ValueError, 'native build'):
            build_release.build(None)

    def test_payload_does_not_ship_fleet_or_custom_exports(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            # Packaging shape fixture only, not claimed to be a runnable executable.
            native = tmp / 'native'
            native.mkdir()
            (native / 'bjrme-generator').write_bytes(b'packaging-mode-fixture')
            if os.name != 'nt':
                (native / 'alias').symlink_to('bjrme-generator')
            target = tmp / 'release.zip'
            with contextlib.redirect_stdout(io.StringIO()):
                build_release.build(target, generator_dir=native)
            with zipfile.ZipFile(target) as z:
                names = z.namelist()
                self.assertEqual(len([n for n in names if n.startswith('BJRME-donors/default/') and n.endswith('.zip')]), 21)
                self.assertFalse(any(n.startswith('BJRME-donors/custom/') and n.endswith('.zip') for n in names))
                self.assertIn('Resources/Server/RacePrep/updater/preflight-required.json', names)
                self.assertIn('Resources/Server/RacePrep/updater/client/lua/ge/extensions/raceprep/ratings-seed.json', names)
                self.assertEqual(z.getinfo('bjrme-generator/bjrme-generator').external_attr >> 16 & 0o111, 0o111)
                self.assertIn('start-bjrme-server.sh', names)
                if os.name != 'nt':
                    self.assertEqual(z.getinfo('bjrme-generator/alias').external_attr >> 16 & 0o170000, 0o120000)
                    self.assertEqual(z.read('bjrme-generator/alias'), b'bjrme-generator')
                self.assertFalse(any(n.endswith('ServerConfig.toml') or n.endswith('.key') for n in names))
                self.assertFalse(any(n.startswith('Resources/Server/BeamJoyServer/') and n.endswith('BeamJoyServer.lua') for n in names))
                with zipfile.ZipFile(io.BytesIO(z.read('Resources/Client/BJR_RacePrep.zip'))) as client:
                    self.assertFalse(any(n.startswith('vehicles/') for n in client.namelist()))

    def test_play_and_custom_editions(self):
        # owner 2026-10-21: play = with the bundled donors, custom = without; both
        # carry the conversion tool and the same expansion
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            native = tmp / 'native'
            native.mkdir()
            (native / 'bjrme-generator').write_bytes(b'packaging-mode-fixture')
            names = {}
            for edition in ('play', 'custom'):
                target = tmp / (edition + '.zip')
                with contextlib.redirect_stdout(io.StringIO()):
                    build_release.build(target, generator_dir=native, edition=edition)
                with zipfile.ZipFile(target) as z:
                    names[edition] = set(z.namelist())
                    import json
                    self.assertEqual(json.loads(z.read('bjrme-release.json'))['edition'], edition)
            donors = lambda e: {n for n in names[e] if n.startswith('BJRME-donors/default/')}
            self.assertEqual(len([n for n in donors('play') if n.endswith('.zip')]), 21)
            self.assertFalse(donors('custom'), 'custom edition ships no bundled donors')
            for e in ('play', 'custom'):
                self.assertIn('BJRME-donors/custom/engines/README.txt', names[e])
                self.assertIn('bjrme-generator/bjrme-generator', names[e], 'both carry the conversion tool')
                for module in ('RacePrep.lua', 'MotorsportSettings.lua', 'Weekend.lua', 'ReleaseUpdates.lua', 'BJRApi.lua'):
                    self.assertIn('Resources/Server/RacePrep/' + module, names[e])
                self.assertFalse(any(n.startswith('Resources/Server/BeamJoyServer/') for n in names[e]), 'nothing added to BJR')
            self.assertEqual(names['play'] - donors('play'), names['custom'], 'editions differ only in the bundled donors')
        with self.assertRaises(ValueError):
            build_release.build(None, edition='deluxe')


if __name__ == '__main__':
    unittest.main()
