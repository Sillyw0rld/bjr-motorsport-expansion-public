# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Native frozen/Python parity gate. Invoke with --executable <native binary>."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from test_distribution import fixture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path)
    args = parser.parse_args()
    if not args.executable:
        print('SKIP: native standalone parity requires --executable')
        return
    binary = args.executable.resolve()
    with tempfile.TemporaryDirectory(prefix='rp native parity é ') as tmp:
        tmp = Path(tmp)
        python_root, native_root = fixture(tmp / 'Python install'), fixture(tmp / 'native install')
        installed = native_root / 'bjrme-generator'
        shutil.copytree(binary.parent, installed, symlinks=True)
        env = dict(os.environ, PATH='', PYTHONPATH='', PYTHONHOME='')
        # Absolute interpreter for reference only; frozen command has no Python on PATH.
        for command, server in [([sys.executable, '-X', 'utf8', '-I', str(ROOT / 'tools/generator.py')], python_root),
                                ([str(installed / binary.name)], native_root)]:
            result = subprocess.run([*command, '--beammp', str(server)], cwd=tmp, env=env,
                                    capture_output=True, text=True, encoding='utf8', timeout=180)
            assert result.returncode == 0, result.stdout + result.stderr
            print(result.stdout.strip())
        rel = 'Resources/Client/BJR_RacePrep.zip'
        assert (python_root / rel).read_bytes() == (native_root / rel).read_bytes(), 'Python/frozen ZIP differs'
        unchanged = (native_root / rel).read_bytes()
        result = subprocess.run([str(installed / binary.name)],
                                cwd=tmp, env=env, capture_output=True, text=True, encoding='utf8', timeout=180)
        assert result.returncode == 0, result.stderr
        assert 'up-to-date' in result.stdout, result.stdout
        assert unchanged == (native_root / rel).read_bytes()
        # A successful preflight launches the target with its normal server cwd
        # and holds the session lock until that process exits.
        success_marker = native_root / 'started-after-preflight'
        code = "from pathlib import Path; import zipfile; assert Path('Resources/Server/RacePrep/updater/server-session.lock').is_dir(); z=zipfile.ZipFile('Resources/Client/BJR_RacePrep.zip'); assert any(n.endswith('.jbeam') for n in z.namelist()); Path('started-after-preflight').touch()"
        result = subprocess.run([str(installed / binary.name), '--beammp', str(native_root),
                                 '--server', sys.executable, '--server-arg=-c', '--server-arg=' + code],
                                cwd=tmp, env=env, capture_output=True, text=True, encoding='utf8', timeout=180)
        assert result.returncode == 0 and success_marker.exists(), result.stdout + result.stderr
        assert not (native_root / 'Resources/Server/RacePrep/updater/server-session.lock').exists()
        # A failed import must prevent both publication and launching the target process.
        bad = native_root / 'BJRME-donors/custom/engines/broken.zip'
        bad.write_bytes(b'bad archive')
        marker = tmp / 'server-was-started'
        result = subprocess.run([str(installed / binary.name), '--beammp', str(native_root),
                                 '--server', sys.executable, '--server-arg=-c',
                                 '--server-arg=' + f'from pathlib import Path; Path({str(marker)!r}).touch()'],
                                cwd=tmp, env=env, capture_output=True, text=True, encoding='utf8', timeout=180)
        assert result.returncode != 0 and not marker.exists(), result.stdout + result.stderr
        assert unchanged == (native_root / rel).read_bytes()
        print('PASS: native standalone/Python byte parity, empty PATH, Unicode/spaces, no-op and failure gate')


if __name__ == '__main__':
    main()
