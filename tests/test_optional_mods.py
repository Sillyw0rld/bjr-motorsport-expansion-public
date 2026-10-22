# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Optional mods (2026-10-21): detection by content, ignore list, reminders,
verified download and staging, installation at the next launcher start."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import optional_mods as om  # noqa: E402


def make_zip(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as z:
        for name, data in files.items():
            z.writestr(name, data)
    return buf.getvalue()


def info(resource, version):
    return json.dumps({'resource_id': resource, 'version_string': version})


class OptionalMods(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / 'Resources/Client').mkdir(parents=True)
        (self.root / 'Resources/Server/RacePrep').mkdir(parents=True)
        self.saved = json.loads(json.dumps(om.MODS))

    def tearDown(self):
        om.MODS.clear()
        om.MODS.update(self.saved)
        self.tmp.cleanup()

    def client(self, name, data):
        (self.root / 'Resources/Client' / name).write_bytes(data)

    def states(self):
        return {s['key']: s['state'] for s in om.detect(self.root)}

    def test_detection_by_content_not_name(self):
        self.assertEqual(self.states(), {'kts': 'missing', 'fluidspill': 'missing', 'ddp': 'missing'})
        # an older KTS under another file name, by its repository resource id
        self.client('my_tyres.zip', make_zip({'mod_info/X/info.json': info(39079, '1.4.0'),
                                              'lua/ge/extensions/career/modules/kagoniTyrePersistence.lua': 'x'}))
        # DDP at the tested version, by resource id and version
        self.client('ddp.zip', make_zip({'mod_info/Y/info.json': info(38670, '2.0'), 'lua/ge/extensions/crashDebris.lua': 'x'}))
        # Fluid Spill without mod_info: recognised by its files, version unknown
        self.client('spills.zip', make_zip({'lua/ge/extensions/fluidspill/main.lua': 'x'}))
        self.assertEqual(self.states(), {'kts': 'outdated', 'fluidspill': 'unknown', 'ddp': 'current'})
        # a Luuk-based tyre mod that isn't KTS is not mistaken for it
        (self.root / 'Resources/Client/my_tyres.zip').unlink()
        self.client('other_tyres.zip', make_zip({'lua/vehicle/extensions/auto/luukstyrethermalsandwear.lua': 'x'}))
        self.assertEqual(self.states()['kts'], 'missing')

    def test_fluid_spill_needs_its_server_plugin(self):
        om.MODS['fluidspill']['client_sha256'] = None
        data = make_zip({'lua/ge/extensions/fluidspill/main.lua': 'x'})
        om.MODS['fluidspill']['client_sha256'] = hashlib.sha256(data).hexdigest()
        self.client('fluidspill-100.zip', data)
        self.assertEqual(self.states()['fluidspill'], 'plugin-missing')
        (self.root / 'Resources/Server/FluidSpill').mkdir()
        (self.root / 'Resources/Server/FluidSpill/main.lua').write_text('x')
        self.assertEqual(self.states()['fluidspill'], 'current')

    def test_reminders_ignore_and_status_file(self):
        lines = om.report(self.root)
        self.assertEqual(len(lines), 3)
        self.assertTrue(all('bjrme get ' in l and 'bjrme optional ignore ' in l for l in lines))
        self.assertIn('beamng.com/resources/', lines[0])
        (self.root / 'Resources/Server/RacePrep/optional-mods.json').write_text(json.dumps({'ignore': ['ddp', 'nope']}))
        lines = om.report(self.root)
        self.assertEqual(len(lines), 2)
        self.assertFalse(any('bjrme get ddp"' in l for l in lines))
        status = json.loads((self.root / 'Resources/Server/RacePrep/optional-mods-status.json').read_text())
        self.assertEqual(status['reminders'], lines)
        self.assertTrue([m for m in status['mods'] if m['key'] == 'ddp'][0]['ignored'])

    def test_download_must_match_the_tested_version(self):
        result = om.get(self.root, 'ddp', download=lambda url: b'not the tested file')
        self.assertEqual(result['status'], 'failed')
        self.assertIn('tested with', result['message'])
        self.assertFalse((self.root / om.WORK / 'staged').exists())
        self.assertEqual(om.get(self.root, 'nope', download=None)['status'], 'failed')

    def test_stage_then_install_replaces_the_old_copy(self):
        new = make_zip({'mod_info/Y/info.json': info(38670, '2.0'), 'lua/ge/extensions/crashDebris.lua': 'new'})
        om.MODS['ddp']['sha256'] = hashlib.sha256(new).hexdigest()
        old = make_zip({'mod_info/Y/info.json': info(38670, '1.2'), 'lua/ge/extensions/crashDebris.lua': 'old'})
        self.client('ddp_old_name.zip', old)
        (self.root / 'Resources/Client/mods.json').write_text(json.dumps({'ddp_old_name.zip': {'protected': False}}))
        seen = []
        result = om.get(self.root, 'ddp', download=lambda url: seen.append(url) or new)
        self.assertEqual(result['status'], 'staged')
        self.assertTrue(seen[0].startswith('https://www.beamng.com/resources/dynamic-damage-particles'))
        self.assertTrue((self.root / 'Resources/Client/ddp_old_name.zip').exists(), 'nothing installed while the server runs')
        msgs = om.apply(self.root)
        self.assertEqual(len(msgs), 1)
        self.assertFalse((self.root / 'Resources/Client/ddp_old_name.zip').exists(), 'old copy moved to a backup, not doubled')
        installed = self.root / 'Resources/Client/dynamic_damage_particles.zip'
        self.assertEqual(installed.read_bytes(), new)
        mods = json.loads((self.root / 'Resources/Client/mods.json').read_text())
        self.assertEqual(mods['dynamic_damage_particles.zip']['hash'], hashlib.sha256(new).hexdigest())
        self.assertEqual(list((self.root / om.WORK).glob('backup-*/ddp/ddp_old_name.zip'))[0].read_bytes(), old)
        self.assertEqual(self.states()['ddp'], 'current')
        self.assertEqual(om.apply(self.root), [], 'staging is consumed once')

    def test_fluid_spill_pack_installs_client_and_server_plugin(self):
        m = om.MODS['fluidspill']
        client = make_zip({'lua/ge/extensions/fluidspill/main.lua': 'x'})
        pack = make_zip({m['pack_client']: client, m['pack_server'] + 'main.lua': 'relay',
                         m['pack_server'] + 'settings.example.json': '{}', m['pack_server'] + '../escape.lua': 'no'})
        m['sha256'], m['client_sha256'] = hashlib.sha256(pack).hexdigest(), hashlib.sha256(client).hexdigest()
        self.assertEqual(om.get(self.root, 'fluidspill', download=lambda url: pack)['status'], 'staged')
        om.apply(self.root)
        self.assertEqual((self.root / 'Resources/Client/fluidspill-100.zip').read_bytes(), client)
        self.assertEqual((self.root / 'Resources/Server/FluidSpill/main.lua').read_text(), 'relay')
        self.assertFalse((self.root / 'Resources/Server/escape.lua').exists())
        self.assertEqual(self.states()['fluidspill'], 'current')

    def test_only_official_hosts(self):
        for url in ('http://www.beamng.com/x', 'https://evil.example/x', 'https://www.beamng.com.evil.example/x'):
            with self.assertRaises(ValueError):
                om.fetch(url)


if __name__ == '__main__':
    unittest.main(verbosity=1)
