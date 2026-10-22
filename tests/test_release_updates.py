# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import release_updates as U


def package(version='2.12.0.999', extra=None):
    exe = 'bjrme-generator.exe' if sys.platform == 'win32' else 'bjrme-generator'
    files = {'Resources/Client/BJR_RacePrep.zip': b'new mod',
             'Resources/Server/RacePrep/ReleaseUpdates.lua': b'new plugin',
             'bjrme-generator/' + exe: b'native fixture',
             'BJRME-donors/default/engines.json': b'new donors'}
    files.update(extra or {})
    manifest = {'format': 1, 'version': version, 'files': {n: hashlib.sha256(b).hexdigest() for n, b in files.items()}}
    files[U.MANIFEST] = json.dumps(manifest).encode()
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w') as z:
        for name, content in files.items():
            z.writestr(name, content)
    return data.getvalue()


class Updates(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rp update é ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.settings = self.root / 'Resources/Server/RacePrep/updates.json'
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({'enabled': True, 'repository': 'author/project'}))
        (self.root / U.MANIFEST).write_text(json.dumps({'version': '2.12.0.1', 'files': {}}))
        self.blob = package()
        self.latest = {'status': 'available', 'latest': 'v2.12.0.999', 'asset': {
            'browser_download_url': 'https://github.com/author/project/releases/download/v2.12.0.999/bjrme-play-linux-x64.zip',
            'digest': 'sha256:' + hashlib.sha256(self.blob).hexdigest()}}

    def stage(self):
        with patch.object(U, 'fetch', return_value=self.blob):
            return U.stage(self.root, self.latest)

    def test_placeholder_makes_no_request(self):
        self.settings.write_text(json.dumps({'repository': U.PLACEHOLDER, 'enabled': True}))
        with patch.object(U, 'fetch', side_effect=AssertionError('must not contact placeholder')):
            self.assertEqual(U.run(self.root, 'check')['status'], 'not-configured')

    def test_latest_check_and_numeric_version(self):
        platform = 'windows' if sys.platform == 'win32' else 'linux'
        names = [f'bjrme-{e}-{platform}-x64.zip' for e in ('play', 'custom')]
        response = json.dumps({'tag_name': 'v2.12.0.10', 'assets': [{'name': n} for n in names]}).encode()
        with patch.object(U, 'fetch', return_value=response):
            result = U.check(self.root)
        self.assertEqual(result['status'], 'available')
        self.assertEqual(result['asset']['name'], names[0], 'no edition recorded: Play')
        # a Custom install only ever takes the Custom archive (no bundled donors)
        (self.root / U.MANIFEST).write_text(json.dumps({'version': '2.12.0.1', 'edition': 'custom', 'files': {}}))
        with patch.object(U, 'fetch', return_value=response):
            self.assertEqual(U.check(self.root)['asset']['name'], names[1])
        self.assertGreater(U.version('2.12.0.10'), U.version('2.12.0.9'))

    def test_stage_apply_backup_and_preserve_local_data(self):
        keep = ['BJRME-donors/custom/engines/mine.zip', 'Resources/Server/RacePrep/rules.json',
                'Resources/Server/RacePrep/ratings.json', 'Resources/Client/my-car.zip',
                'Resources/Server/BeamJoyServer/BeamJoyServer.lua', 'Resources/Server/RacePrep/history/race.json']
        for name in keep:
            p = self.root / name;p.parent.mkdir(parents=True, exist_ok=True);p.write_bytes(b'keep')
        old = self.root / 'Resources/Client/BJR_RacePrep.zip';old.write_bytes(b'old mod')
        self.assertEqual(self.stage()['status'], 'staged')
        self.assertEqual(old.read_bytes(), b'old mod', 'staging never changes running server files')
        result = U.run(self.root, 'apply')
        self.assertEqual(result['status'], 'installed', result)
        self.assertEqual(old.read_bytes(), b'new mod')
        self.assertFalse((self.root / '.raceprep-update/ready.json').exists())
        self.assertTrue(list((self.root / '.raceprep-update/backups').rglob('BJR_RacePrep.zip')))
        for name in keep:
            self.assertEqual((self.root / name).read_bytes(), b'keep')

    def test_bad_checksum_and_unsafe_release_refused(self):
        self.latest['asset']['digest'] = 'sha256:' + '0' * 64
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.stage()
        for name in ['../escape', 'Resources/Server/RacePrep/rules.json', 'Resources/Server/BeamJoyServer/BeamJoyServer.lua']:
            with self.assertRaises(ValueError):
                U.unpack(package(extra={name: b'bad'}), self.root / 'reject', '2.12.0.999')
        for url in ['http://github.com/author/project', 'https://other.example/file']:
            with self.assertRaises(ValueError):
                U.fetch(url)

    def test_active_lock_and_tampering_refused(self):
        self.stage()
        lock = self.root / 'Resources/Server/RacePrep/updater/server-session.lock'
        lock.mkdir(parents=True)
        self.assertEqual(U.run(self.root, 'apply')['status'], 'failed')
        lock.rmdir()
        (self.root / '.raceprep-update/payload/Resources/Client/BJR_RacePrep.zip').write_bytes(b'tampered')
        self.assertEqual(U.run(self.root, 'apply')['status'], 'failed')
        self.assertFalse((self.root / 'Resources/Client/BJR_RacePrep.zip').exists())

    def test_install_failure_rolls_back_written_files(self):
        old = self.root / 'Resources/Client/BJR_RacePrep.zip';old.parent.mkdir(parents=True);old.write_bytes(b'old')
        self.stage()
        real = U.os.replace
        def fail(src, dest):
            if str(dest).endswith('ReleaseUpdates.lua'):
                raise PermissionError('simulated locked file')
            return real(src, dest)
        with patch.object(U.os, 'replace', side_effect=fail):
            result = U.run(self.root, 'apply')
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(old.read_bytes(), b'old')
        self.assertTrue((self.root / '.raceprep-update/ready.json').exists())


if __name__ == '__main__':
    unittest.main()
