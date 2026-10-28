#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Run on each target OS with packaging/requirements.txt installed."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import tempfile
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dist', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if platform.machine().lower() not in ('x86_64', 'amd64') or sys.platform not in ('linux', 'win32'):
        parser.error('Build natively on Windows x64 or Linux x64')
    # Collect modules dynamically used by the established builders. Include
    # source/data at their existing paths: their ROOT-relative readers are shared.
    command = [sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onedir',
               '--python-option', 'X utf8', '--name', 'bjrme-generator', '--distpath', str(args.dist.resolve()),
               '--workpath', str(ROOT / 'build/pyinstaller'), '--specpath', str(ROOT / 'build'),
               '--paths', str(ROOT / 'tools'), '--collect-submodules', 'engine_swaps',
               '--collect-submodules', 'drivetrain_conversions']
    # Linux Python ships its libraries with debug info (about 12 MB zipped);
    # Windows keeps it in separate .pdb files, and PyInstaller advises against strip there.
    if sys.platform == 'linux':
        command.append('--strip')
    with tempfile.TemporaryDirectory(prefix='rp-freeze-data-') as tmp:
        staged = Path(tmp)
        for folder in ('tools', 'client/lua'):
            for source in sorted((ROOT / folder).rglob('*')):
                if source.is_file() and source.suffix in ({'.py', '.json', '.lua'} if folder == 'tools' else {'.json'}):
                    destination = staged / source.relative_to(ROOT)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, destination)
            command.extend(['--add-data', str(staged / folder) + os.pathsep + folder])
        command.append(str(ROOT / 'tools/generator.py'))
        subprocess.run(command, cwd=ROOT, check=True)



if __name__ == '__main__':
    main()
