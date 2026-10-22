#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Shared standalone/developer preflight. Run before starting BeamMP."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))


def server_environment():
    """Undo frozen library search overrides before launching the host server."""
    env = dict(os.environ)
    if getattr(sys, 'frozen', False):
        if sys.platform == 'linux':
            if 'LD_LIBRARY_PATH_ORIG' in env:
                env['LD_LIBRARY_PATH'] = env.pop('LD_LIBRARY_PATH_ORIG')
            else:
                env.pop('LD_LIBRARY_PATH', None)
        elif sys.platform == 'win32':
            import ctypes
            if not ctypes.windll.kernel32.SetDllDirectoryW(None):
                raise OSError('Could not restore Windows DLL search path for BeamMP')
    return env


def optional_start(root):
    """Launcher start: install staged optional mods, then remind about missing ones (never fatal)."""
    try:
        import optional_mods
        for line in optional_mods.apply(root) + optional_mods.report(root):
            print('[BJR:ME] ' + line, flush=True)
    except Exception as e:
        print(f'[BJR:ME] Optional mods check skipped: {e}', flush=True)


def optional_request(root, key, request_id):
    """Console request (server running): check, or download and stage one mod."""
    import re
    import time
    import optional_mods
    work = root / optional_mods.WORK
    if request_id is not None and not re.fullmatch(r'[0-9]+-[0-9]+', request_id):
        return 1
    try:
        if key:
            result = optional_mods.get(root, key)
        else:
            reminders = optional_mods.report(root)
            result = {'status': 'checked', 'message': ' | '.join(reminders) or 'All optional mods are installed at their tested versions (or ignored).'}
    except Exception as e:
        result = {'status': 'failed', 'message': str(e)}
    result.update(requestId=request_id, finishedAt=int(time.time()))
    if request_id:
        optional_mods.atomic_json(work / ('request-' + request_id + '.json'), result)
    print(json.dumps(result), flush=True)
    return 1 if result['status'] == 'failed' else 0


def main(argv=None):
    installed = Path(sys.executable).resolve().parent.parent if getattr(sys, 'frozen', False) else HERE.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--beammp', type=Path, default=installed, help='BeamMP server directory')
    ap.add_argument('--donors', type=Path, help='default/custom donor root (default: server/BJRME-donors)')
    ap.add_argument('--check', action='store_true', help='report pending generation without replacing assets')
    ap.add_argument('--server', type=Path, help='start this BeamMP executable only after successful preflight')
    ap.add_argument('--server-arg', action='append', default=[])
    ap.add_argument('--update-request-id', help=argparse.SUPPRESS)
    updates = ap.add_mutually_exclusive_group()
    updates.add_argument('--update-check', action='store_true', help='check the configured GitHub release')
    updates.add_argument('--update-stage', action='store_true', help='verify/download an update for the next launcher start')
    updates.add_argument('--update-apply', action='store_true', help=argparse.SUPPRESS)
    updates.add_argument('--optional-check', action='store_true', help='report optional mods (KTS, Fluid Spill, Dynamic Damage Particles)')
    updates.add_argument('--optional-get', metavar='MOD', help='download and stage an optional mod from its official page')
    ap.add_argument('--optional-request-id', help=argparse.SUPPRESS)
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args(argv)
    args.beammp = args.beammp.resolve()
    if args.update_check or args.update_stage or args.update_apply:
        if args.server or args.check:
            ap.error('release update actions cannot be combined with --server or parts --check')
        from release_updates import run
        try:
            result = run(args.beammp, 'apply' if args.update_apply else 'stage' if args.update_stage else 'check', request_id=args.update_request_id)
        except Exception as e:
            result = {'status': 'failed', 'message': str(e)}
        print(json.dumps(result), flush=True)
        return 1 if result['status'] in ('failed', 'busy') else 0
    if args.optional_check or args.optional_get:
        if args.server or args.check:
            ap.error('optional-mod actions cannot be combined with --server or parts --check')
        return optional_request(args.beammp, args.optional_get, args.optional_request_id)
    donors = args.donors or args.beammp / 'BJRME-donors'
    session = args.beammp / 'Resources/Server/RacePrep/updater/server-session.lock'
    owns_session = False
    try:
        if args.server and args.check:
            raise ValueError('--check cannot start a server')
        if session.exists():
            raise RuntimeError(f'Server launcher is already active, or was interrupted: {session}. Stop it before generating; inspect processes before removing a stale lock')
        if args.server:
            session.parent.mkdir(parents=True, exist_ok=True)
            session.mkdir()
            owns_session = True
            optional_start(args.beammp)
        from incremental_generation import update
        result = update(args.beammp, args.verbose, donors, args.check, server_session=owns_session)
        print(json.dumps(result), flush=True)
        if args.server:
            server = args.server if args.server.is_absolute() else args.beammp / args.server
            return subprocess.call([str(server.resolve()), *args.server_arg], cwd=args.beammp, env=server_environment())
        return 0
    except Exception as e:
        print(f'[BJR:ME] Preflight/server startup failed: {e}. Check the named source or install path before retrying.', file=sys.stderr, flush=True)
        return 1
    finally:
        if owns_session:
            session.rmdir()


if __name__ == '__main__':
    sys.exit(main())
