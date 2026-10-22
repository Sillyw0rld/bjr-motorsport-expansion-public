#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Run offline Race Prep regressions from the repository root."""
import subprocess
import json
import os
from pathlib import Path
root=Path(__file__).resolve().parents[1]
os.environ['LUA_PATH']=str(root/'client/lua/?.lua')+';'+os.environ.get('LUA_PATH',';;')
for test in sorted((root/'tests').glob('test_*.lua')):
    print(f"\n{test.name}",flush=True)
    subprocess.run(['luajit',str(test.relative_to(root))],cwd=root,check=True)
for test in sorted((root/'tests').glob('test_*.py')):
    subprocess.run(['python3','-I',str(test)],cwd=root,check=True)
for file in sorted(root.rglob('*.lua')):
    if '.git' not in file.parts:
        subprocess.run(['luajit','-e','assert(loadfile(' + json.dumps(str(file)) + '))'],cwd=root,check=True)
for file in [root/'build_release.py',*sorted((root/'tools').rglob('*.py'))]:
    compile(file.read_text(),str(file),'exec')
print('PASS: all offline suites and Lua/Python syntax checks')
