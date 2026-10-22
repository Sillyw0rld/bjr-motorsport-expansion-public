#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Server-side upgrade-parts updater for Motorsport Expansion (BJR:ME).

Developer compatibility CLI for the shared transactional preflight updater.
Public installations use generator.py / the standalone launcher before BeamMP
starts. Changed inputs and invalid outputs are regenerated in staging; unchanged
cars retain their outputs. Do not run a writer while BeamMP is running.

usage: parts_updater.py --beammp <BeamMP server folder> [--check] [-v]
Writes <updater folder>/last-run.json: {status: up-to-date|updated|failed, newCars, seconds, error}
"""
import argparse
import json
import os
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
ZIP_NAME = 'BJR_RacePrep.zip'
CATALOGUES = ['lua/ge/extensions/raceprep/upgrade-parts.json', 'lua/common/raceprep/engine-parts.json',
              'vehicles/rp_engine_swaps/raceprep/rp_swap_library.json',
              'vehicles/rp_drivetrain_conversions/raceprep/rp_drivetrain_library.json']


def shipped_models(zip_path):
    """car models that already have parts in the shipped zip"""
    with zipfile.ZipFile(zip_path) as z:
        cat = json.loads(z.read(CATALOGUES[0]))
    return {k.split('/')[0] for k in cat.get('stocks', {})}


def add_only(old, new):
    """merge JSON: keys missing in old are added; existing keys are kept as they are"""
    if not isinstance(old, dict) or not isinstance(new, dict):
        return old
    out = dict(old)
    for k, v in new.items():
        out[k] = add_only(old[k], v) if k in old else v
    return out


def write_zip(src_dir, target):
    """deterministic zip of src_dir, replaced atomically"""
    tmp = target.with_name(target.name + '.tmp')
    files = sorted(p for p in src_dir.rglob('*') if p.is_file())
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in files:
            info = zipfile.ZipInfo(p.relative_to(src_dir).as_posix(), date_time=(2026, 10, 15, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, p.read_bytes())
    os.replace(tmp, target)


def update(beammp, verbose=False):
    """Compatibility entry point; use the same transactional pipeline as preflight."""
    from incremental_generation import update as incremental_update
    root = Path(beammp) / 'BJRME-donors'
    if not root.exists():
        from runtime_paths import ROOT
        root = ROOT / 'donors'
    return incremental_update(beammp, verbose, root)


def shipped_models_dir(root):
    cat = json.loads((root / CATALOGUES[0]).read_text())
    return {k.split('/')[0] for k in cat.get('stocks', {})}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--beammp', type=Path, default=Path.cwd(), help='BeamMP server folder (default: current folder)')
    ap.add_argument('--check', action='store_true', help='only report cars without parts; change nothing')
    ap.add_argument('--seed-state', action='store_true',
                    help='record the installed ZIP as current for the cars it has parts for (after a deploy); generates nothing')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()
    started = time.time()
    result_file = HERE / 'last-run.json'
    try:
        if a.seed_state:
            from incremental_generation import seed
            donor_root = a.beammp / 'BJRME-donors'
            if not donor_root.exists():
                from runtime_paths import ROOT
                donor_root = ROOT / 'donors'
            result = seed(a.beammp.resolve(), donor_root)
            print(f"[BJR:ME] generation state recorded for {result['cars']} cars"
                  + (f"; without parts (built at next start): {', '.join(result['withoutParts'])}" if result['withoutParts'] else ''), flush=True)
        elif a.check:
            from incremental_generation import update as incremental_update
            donor_root = a.beammp / 'BJRME-donors'
            if not donor_root.exists():
                from runtime_paths import ROOT
                donor_root = ROOT / 'donors'
            result = incremental_update(a.beammp, a.verbose, donor_root, check=True)
        else:
            result = update(a.beammp.resolve(), a.verbose)
    except Exception as e:  # the server must start anyway; report why
        result = {'status': 'failed', 'newCars': [], 'error': f'{type(e).__name__}: {e}'}
    result['seconds'] = round(time.time() - started, 1)
    result['finished'] = time.strftime('%Y-%m-%d %H:%M:%S')
    result['finishedAt'] = int(time.time())  # the plugin ignores results older than its start
    if not a.check and not a.seed_state:
        # written in place: replacing or deleting files under Resources/Server makes
        # BeamMP's plugin file monitor log warnings (a half-written read is retried)
        result_file.write_text(json.dumps(result, indent=1) + '\n')
    print(json.dumps(result), flush=True)
    return 0 if result['status'] != 'failed' else 1


if __name__ == '__main__':
    sys.exit(main())
