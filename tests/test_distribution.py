# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Distribution lifecycle against small real author-owned Automation sources."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import donor_registry as D
import incremental_generation as G
from drivetrain_conversions.library import verify_and_extract_donors
from jbeam_json import loads


def fixture(root):
    client = root / 'Resources/Client'
    client.mkdir(parents=True)
    shutil.copytree(ROOT / 'donors', root / 'BJRME-donors')
    shutil.copyfile(ROOT / 'donors/default/engines/hawk_el_chapo.zip', client / 'recipient.zip')
    with zipfile.ZipFile(client / 'BJR_RacePrep.zip', 'w') as z:
        z.writestr('untouched.txt', 'preserve unrelated expansion assets')
    return root


def clone(source, target, suffix='_custom', extra=False):
    """Same physical data, distinct supported model identity; no fabricated engine."""
    with zipfile.ZipFile(source) as src, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as dst:
        for name in src.namelist():
            bits = name.split('/')
            model = bits[1]
            data = src.read(name)
            if Path(name).suffix != '.car':
                data = data.replace(model.encode(), (model + suffix).encode())
            dst.writestr(name.replace('/' + model + '/', '/' + model + suffix + '/'), data)
        if extra:
            dst.writestr('irrelevant.txt', 'not donor physics')


def quiet_update(*args, **kwargs):
    with contextlib.redirect_stdout(io.StringIO()):
        return G.update(*args, **kwargs)


class Distribution(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = tempfile.TemporaryDirectory(prefix='rp distribution é ')
        cls.root = fixture(Path(cls.base.name) / 'baseline')
        cls.donors = cls.root / 'BJRME-donors'
        cls.first = quiet_update(cls.root, donors=cls.donors)

    @classmethod
    def tearDownClass(cls):
        cls.base.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rp case é ')
        self.addCleanup(self.tmp.cleanup)
        self.server = Path(self.tmp.name) / 'server with spaces'
        shutil.copytree(self.root, self.server)
        self.donors = self.server / 'BJRME-donors'
        self.archive = self.server / 'Resources/Client/BJR_RacePrep.zip'

    def update(self, **kwargs):
        return quiet_update(self.server, donors=self.donors, **kwargs)

    def test_first_run_no_change_and_determinism(self):
        self.assertEqual(self.first['status'], 'updated')
        self.assertGreater(self.first['parts'], 500)
        before = self.archive.read_bytes()
        self.assertEqual(self.update()['status'], 'up-to-date')
        self.assertEqual(self.archive.read_bytes(), before)
        (self.server / 'Resources/Server/RacePrep/updater/generation-state.json').unlink()
        self.assertEqual(self.update()['status'], 'updated')
        self.assertEqual(self.archive.read_bytes(), before)
        with zipfile.ZipFile(self.archive) as z:
            self.assertEqual(z.read('untouched.txt'), b'preserve unrelated expansion assets')
            self.assertNotIn(str(self.server).encode(), b''.join(z.read(n) for n in G.CATALOGUES))

    def test_seed_state_keeps_the_deployed_zip(self):
        # live deploy (2.15): the installed ZIP was built with measured data; the
        # seeded state stops the next start from regenerating it with derived values
        state = self.server / 'Resources/Server/RacePrep/updater/generation-state.json'
        state.unlink()
        before = self.archive.read_bytes()
        seeded = G.seed(self.server, self.donors)
        self.assertEqual(seeded['status'], 'seeded')
        self.assertEqual(seeded['withoutParts'], [])
        self.assertEqual(self.update()['status'], 'up-to-date')
        self.assertEqual(self.archive.read_bytes(), before)
        # a car added after the build is not recorded: the next start builds it
        clone(self.server / 'Resources/Client/recipient.zip', self.server / 'Resources/Client/new.zip')
        state.unlink()
        seeded = G.seed(self.server, self.donors)
        self.assertEqual(seeded['withoutParts'], ['hawk_el_chapo_custom'])
        self.assertIn('hawk_el_chapo_custom', self.update()['newCars'])

    def test_custom_edition_without_bundled_donors(self):
        # Custom edition: no BJRME-donors/default; engine donors are the
        # administrator's own; drivetrain conversions need their own FWD/RWD/AWD set
        import donor_registry
        shutil.rmtree(self.donors / 'default')
        registry = donor_registry.load(self.donors)
        self.assertEqual(registry['edition'], 'custom')
        self.assertEqual(registry['counts'], {'default': 0, 'custom': 0})
        self.assertEqual(donor_registry.drivetrain_set(registry), [], 'no full set: drivetrain conversions off')
        (self.server / 'Resources/Server/RacePrep/updater/generation-state.json').unlink()
        result = self.update()
        self.assertEqual(result['status'], 'updated', 'the conversion tool runs without bundled donors')
        # an incomplete default folder is a damaged install, not the custom edition
        (self.donors / 'default').mkdir()
        with self.assertRaisesRegex(ValueError, 'Missing bundled donor manifest'):
            donor_registry.load(self.donors)

    def test_corrupt_output_and_catalogue_repaired(self):
        before = self.archive.read_bytes()
        with zipfile.ZipFile(self.archive) as z:
            entries = {n: z.read(n) for n in z.namelist()}
        key = next(n for n in entries if n.endswith('.jbeam'))
        del entries[key]
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, value in entries.items():
                z.writestr(name, value)
        self.assertEqual(self.update()['status'], 'updated')
        self.assertEqual(before, self.archive.read_bytes())
        entries[G.CATALOGUES[0]] = b'{broken catalogue'
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, value in entries.items():
                z.writestr(name, value)
        self.assertEqual(self.update()['status'], 'updated')
        self.assertEqual(before, self.archive.read_bytes())

    def test_invalid_donor_and_generation_failure_keep_previous_zip(self):
        before = self.archive.read_bytes()
        bad = self.donors / 'custom/engines/broken.zip'
        bad.write_bytes(b'not a ZIP')
        with self.assertRaises(ValueError):
            self.update()
        self.assertEqual(before, self.archive.read_bytes())
        bad.unlink()
        (self.server / 'Resources/Server/RacePrep/updater/generation-state.json').unlink()
        with patch('generate_upgrades.run', side_effect=ValueError('incomplete parts')):
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                self.update()
        self.assertEqual(before, self.archive.read_bytes())
        self.assertFalse((self.server / 'Resources/Server/RacePrep/updater/generation.lock').exists())

    def test_default_pins_and_duplicate_import(self):
        src = self.donors / 'default/engines/hawk_el_chapo.zip'
        shutil.copyfile(src, self.donors / 'custom/engines/duplicate.zip')
        registry = D.load(self.donors)
        self.assertEqual(registry['counts'], {'default': 21, 'custom': 0})
        self.assertEqual(self.update()['status'], 'up-to-date')
        src.write_bytes(src.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'changed bundled donor'):
            D.load(self.donors)

    def test_custom_engine_update_conflict_removal(self):
        src = self.donors / 'default/engines/hawk_el_chapo.zip'
        custom = self.donors / 'custom/engines/another.zip'
        clone(src, custom)
        self.assertEqual(self.update()['status'], 'updated')
        registry = D.load(self.donors)
        self.assertEqual(registry['counts']['custom'], 1)
        ident = registry['engines'][-1]['donorID']
        shutil.copyfile(custom, custom.with_name('duplicate.zip'))
        self.assertEqual(D.load(self.donors)['counts']['custom'], 1)
        custom.with_name('duplicate.zip').unlink()
        with zipfile.ZipFile(custom) as z:
            entries = {n: z.read(n) for n in z.namelist()}
        # Relevant metadata update retains identity; never retune engine values.
        entries['vehicles/hawk_el_chapo_custom/update.json'] = b'{"revision":2}'
        with zipfile.ZipFile(custom, 'w') as z:
            for n, b in entries.items():
                z.writestr(n, b)
        self.assertEqual(D.load(self.donors)['engines'][-1]['donorID'], ident)
        self.assertEqual(self.update()['status'], 'updated')
        clone(src, custom.with_name('conflict.zip'))
        with self.assertRaisesRegex(ValueError, 'Conflicting donor'):
            self.update()
        custom.with_name('conflict.zip').unlink()
        custom.unlink()
        self.assertEqual(self.update()['status'], 'updated')
        self.assertEqual(self.update()['status'], 'up-to-date')
        with zipfile.ZipFile(self.archive) as z:
            catalog = json.loads(z.read(G.CATALOGUES[2]))
        self.assertFalse(any(d['model'].endswith('_custom') for d in catalog['donors']))

    def test_custom_drivetrains_each_layout_and_independent_engine(self):
        for src in sorted((self.donors / 'default/drivetrains').glob('*.zip')):
            clone(src, self.donors / 'custom/drivetrains' / src.name)
        registry = D.load(self.donors)
        self.assertEqual(registry['counts']['custom'], 3)
        self.assertEqual(self.update()['status'], 'updated')
        with zipfile.ZipFile(self.archive) as z:
            catalog = json.loads(z.read(G.CATALOGUES[3]))
        self.assertEqual(len(catalog['donors']), 6)
        options = catalog['models']['hawk_el_chapo']['options']
        custom = [o for o in options if o.get('donorID')]
        self.assertEqual({o['layout'] for o in custom}, {'FWD', 'RWD', 'AWD'})
        self.assertTrue(any(o.get('part') for o in custom))
        self.assertFalse(any(d['model'].endswith('_custom') for d in registry['engines']))

    def test_new_removed_vehicle_and_check_only(self):
        client = self.server / 'Resources/Client'
        clone(client / 'recipient.zip', client / 'new.zip')
        before = self.archive.read_bytes()
        self.assertEqual(self.update(check=True)['status'], 'check')
        self.assertEqual(self.archive.read_bytes(), before)
        result = self.update()
        self.assertIn('hawk_el_chapo_custom', result['newCars'])
        self.assertEqual(set(result['newCars']) - {'hawk_el_chapo_custom'}, {'hawk_el_chapo'},
                         'new compound source changes the existing car tyre selection fingerprint')
        (client / 'new.zip').unlink()
        result = self.update()
        self.assertEqual(result['removedCars'], ['hawk_el_chapo_custom'])
        with zipfile.ZipFile(self.archive) as z:
            self.assertFalse(any('/hawk_el_chapo_custom/' in n for n in z.namelist()))
            self.assertEqual(z.read('untouched.txt'), b'preserve unrelated expansion assets')

    def test_default_source_pins_mass_and_structure_identity(self):
        registry = D.load(self.donors)
        for donor in registry['engines']:
            with zipfile.ZipFile(donor['archive']) as z:
                self.assertEqual(D.sha(z.read(donor['carMember'])), donor['carSha256'])
                self.assertEqual(D.sha(z.read(donor['engineMember'])), donor['engineSha256'])
        with tempfile.TemporaryDirectory() as tmp:
            _, dt = D.manifests(registry, tmp)
            extracted = verify_and_extract_donors(dt)
        self.assertEqual({k: v['drivetrainMassKG'] for k, v in extracted.items()},
                         {'FWD': 679.838, 'RWD': 710.458, 'AWD': 776.365})
        src = next((self.donors / 'default/drivetrains').glob('*fwd*.zip'))
        target = self.donors / 'custom/drivetrains/renamed.zip'
        clone(src, target, suffix='_renamed')
        with zipfile.ZipFile(target) as z:
            entries = {n: z.read(n) for n in z.namelist()}
        with zipfile.ZipFile(target, 'w') as z:
            for i, (name, content) in enumerate(entries.items()):
                if name.endswith('.jbeam'):
                    name = str(Path(name).with_name(f'actual_configured_part_{i}.jbeam')).replace('\\', '/')
                z.writestr(name, content)
        shutil.copyfile(target, self.donors / 'custom/engines/both.zip')
        selected = D.load(self.donors)
        self.assertEqual(selected['counts']['custom'], 2)
        self.assertEqual(self.update()['status'], 'updated')

    def test_corrupt_existing_vehicle_and_active_server_preserve_assets(self):
        before = self.archive.read_bytes()
        (self.server / 'Resources/Client/recipient.zip').write_bytes(b'corrupted')
        with self.assertRaisesRegex(ValueError, 'no longer readable'):
            self.update()
        self.assertEqual(before, self.archive.read_bytes())
        session = self.server / 'Resources/Server/RacePrep/updater/server-session.lock'
        session.mkdir()
        with self.assertRaisesRegex(RuntimeError, 'launcher is active'):
            self.update()
        self.assertEqual(before, self.archive.read_bytes())

    def test_lock_and_jbeam_validation(self):
        lock = self.server / 'Resources/Server/RacePrep/updater/generation.lock'
        lock.mkdir()
        with self.assertRaisesRegex(RuntimeError, 'Another generator'):
            self.update()
        self.assertEqual(loads('{"a": {"nodes": [["id", "x", "y", "z"] ["a", 0, 0, 0],],},}'),
                         {'a': {'nodes': [['id', 'x', 'y', 'z'], ['a', 0, 0, 0]]}})
        with self.assertRaises(ValueError):
            loads('{"broken": [1, 2}')


if __name__ == '__main__':
    unittest.main()
