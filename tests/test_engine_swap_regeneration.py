# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Build pipeline persistence, bounded cleanup, and pinned source safety."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import generate_engine_swaps as swaps
from generate_upgrades import clean


class Regeneration(unittest.TestCase):
    def test_build_hook_registered(self):
        source = (ROOT / 'tools/generate_upgrades.py').read_text()
        self.assertIn('generate_engine_swaps.generate(resources, output)', source)

    def test_regenerate_after_build_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            resources, out = base / 'sources', base / 'client'
            resources.mkdir()
            cars = {}
            recipe = {'recipient': 'r', 'donor': 'd', 'recipientConfig': 'stock', 'donorConfig': 'stock'}
            for role in ('recipient', 'donor'):
                model = recipe[role]
                path = resources / (model + '.zip')
                path.write_bytes(model.encode())
                cars[model] = {'archive': str(path)}
                recipe[role + 'ArchiveSha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            recipes = base / 'recipes.json'
            recipes.write_text(json.dumps({'version': 1, 'recipes': [recipe]}))
            inventory = {'engines': [{'model': m, 'config': 'stock'} for m in cars], 'errors': []}

            def fake_build(data, recipient, donor, staging):
                folder = staging / 'vehicles' / recipient / 'rp_swap'
                folder.mkdir(parents=True)
                (folder / 'engine.jbeam').write_text('{"donor":"real part data"}')
                (folder.parent / 'private-test.pc').write_text('{}')
                return {'part': 'rp_swap_d_engine', 'prototype': True}

            folder = out / 'vehicles/r/raceprep'
            folder.mkdir(parents=True)
            (folder / 'factory.pc').write_text('keep setup')
            with patch.object(swaps.fleet, 'discover', return_value=cars), \
                    patch.object(swaps.catalogue, 'scan', return_value=inventory), \
                    patch.object(swaps, 'build', side_effect=fake_build):
                result = swaps.generate(resources, out, recipes)
                self.assertEqual(result['generated'], 1)
                files = {str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()}
                self.assertNotIn('vehicles/r/private-test.pc', files)
                manifest = json.loads((folder / 'rp_swap_manifest.json').read_text())
                self.assertEqual(manifest['requiresInstalledDonor'], 'd')
                clean(out)  # same cleanup run by generate_upgrades.py / builds
                self.assertFalse(list(folder.glob('rp_swap_*.jbeam')))
                swaps.generate(resources, out, recipes)
                self.assertEqual(files, {str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()})
                # Refuse changed inputs before removing the last generated copy.
                Path(cars['d']['archive']).write_bytes(b'new, unvalidated donor')
                with self.assertRaisesRegex(ValueError, 'archive changed'):
                    swaps.generate(resources, out, recipes)
                self.assertTrue((folder / 'rp_swap_d_engine.jbeam').exists())
                # Removing a required car retires its generated swap, not setups.
                del cars['d']
                result = swaps.generate(resources, out, recipes)
                self.assertEqual(result['generated'], 0)
                self.assertEqual(len(result['skipped']), 1)
                self.assertFalse(list(folder.glob('rp_swap*')))
                self.assertEqual((folder / 'factory.pc').read_text(), 'keep setup')
                self.assertEqual(Path(cars['r']['archive']).read_bytes(), b'r')


if __name__ == '__main__':
    unittest.main()
