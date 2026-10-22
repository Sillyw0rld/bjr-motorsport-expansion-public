# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""parts_updater: add-only merge never changes existing cars; deterministic zip.
The full end-to-end run (a car removed from the shipped zip comes back
byte-identical) was checked on 2026-10-19 against the live fleet (65 s)."""
import json, sys, tempfile, unittest, zipfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import parts_updater as U


class AddOnly(unittest.TestCase):
    def test_existing_keys_kept_new_added(self):
        old = {'parts': {'a_tyre': {'model': 'a', 'grip': 1.0}}, 'stocks': {'a/front': {'w': 1}}}
        new = {'parts': {'a_tyre': {'model': 'a', 'grip': 9.9}, 'b_tyre': {'model': 'b'}}, 'stocks': {'b/front': {'w': 2}}}
        m = U.add_only(old, new)
        self.assertEqual(m['parts']['a_tyre']['grip'], 1.0, 'an existing car is never regenerated')
        self.assertIn('b_tyre', m['parts']); self.assertIn('b/front', m['stocks']); self.assertIn('a/front', m['stocks'])

    def test_zip_deterministic_and_atomic(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td); (td / 'src/lua').mkdir(parents=True); (td / 'src/lua/x.json').write_text('{}')
            U.write_zip(td / 'src', td / 'a.zip'); U.write_zip(td / 'src', td / 'b.zip')
            self.assertEqual((td / 'a.zip').read_bytes(), (td / 'b.zip').read_bytes())
            self.assertFalse((td / 'a.zip.tmp').exists())
            self.assertEqual(zipfile.ZipFile(td / 'a.zip').namelist(), ['lua/x.json'])

    def test_shipped_models(self):
        with tempfile.TemporaryDirectory() as td:
            z = Path(td) / 'BJR_RacePrep.zip'
            with zipfile.ZipFile(z, 'w') as f:
                f.writestr(U.CATALOGUES[0], json.dumps({'parts': {}, 'stocks': {'car_a/front': {}, 'car_a/rear': {}, 'car_b/front': {}}}))
            self.assertEqual(U.shipped_models(z), {'car_a', 'car_b'})


if __name__ == '__main__':
    unittest.main()
