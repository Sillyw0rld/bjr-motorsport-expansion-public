# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Transactional manifest/cache around the existing generation pipeline."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import zipfile

import donor_registry
import fleet
from parts_updater import CATALOGUES, ZIP_NAME, write_zip

from runtime_paths import ROOT


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    """Provenance stays portable; never embed a staging or installation path."""
    if isinstance(value, dict):
        return {k: Path(v).name if k == 'archive' and isinstance(v, str) else canonical(v)
                for k, v in value.items()}
    if isinstance(value, list):
        return [canonical(v) for v in value]
    return value


def generator_hash():
    entries = [(p.relative_to(ROOT).as_posix(), digest(p.read_bytes()))
               for folder in ('tools', 'client/lua') for p in sorted((ROOT / folder).rglob('*'))
               if p.is_file() and p.suffix in ('.py', '.json')]
    return digest(json.dumps(entries).encode())


def inspect(beammp, donors=None):
    beammp = Path(beammp).resolve()
    client = beammp / 'Resources/Client'
    if not client.is_dir():
        raise ValueError(f'Missing client directory: {client}')
    archive = client / ZIP_NAME
    if not archive.is_file():
        raise ValueError(f'Missing expansion ZIP: {archive}')
    state_dir = beammp / 'Resources/Server/RacePrep/updater'
    state_path = state_dir / 'generation-state.json'
    try:
        previous = json.loads(state_path.read_text())
    except (OSError, ValueError):
        previous = {}
    if not isinstance(previous, dict) or previous.get('version') != 1:
        previous = {}
    registry = donor_registry.load(donors)
    source = canonical({k: registry[k] for k in ('engines', 'drivetrains')})
    inputs = {'generator': generator_hash(), 'donors': digest(json.dumps(source, sort_keys=True).encode()), 'cars': {}}
    cars = fleet.discover(client)
    for model, row in sorted(cars.items()):
        path = Path(row['archive'])
        stat = path.stat()
        stamp = [str(path), stat.st_size, stat.st_mtime_ns]
        old = previous.get('inputs', {}).get('cars', {}).get(model, {})
        hashed = old.get('sha256') if old.get('stamp') == stamp else digest(path.read_bytes())
        inputs['cars'][model] = {'sha256': hashed, 'config': row['config'], 'stamp': stamp}
    old_inputs = previous.get('inputs', {})
    all_changed = any(inputs[k] != old_inputs.get(k) for k in ('generator', 'donors'))
    changed = {m for m, r in inputs['cars'].items() if all_changed or
               any(r[k] != old_inputs.get('cars', {}).get(m, {}).get(k) for k in ('sha256', 'config'))}
    removed = set(old_inputs.get('cars', {})) - set(cars)
    for model in removed:
        old_path = old_inputs['cars'][model].get('stamp', [''])[0]
        candidate = client / Path(old_path).name
        if candidate.is_file() and not any(Path(c['archive']) == candidate for c in cars.values()):
            raise ValueError(f'{candidate.name}: previously supported vehicle {model} is no longer readable; previous outputs retained')
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        for name, expected in previous.get('outputs', {}).items():
            if name not in names or digest(z.read(name)) != expected:
                if name in CATALOGUES:
                    changed.update(cars)
                else:
                    changed.add(name.split('/')[1])
    # Tyre compound choices also depend on other cars' source sets. Recompute
    # selection fingerprints only when fleet bytes/configs or generator change;
    # invalidate only recipients whose actual compound donor selection changes.
    if changed or removed or all_changed:
        import audit_upgrade_sources
        import generate_upgrade_tyres as tyres
        seed = json.loads((ROOT / 'client/lua/ge/extensions/raceprep/ratings-seed.json').read_text())
        audit = audit_upgrade_sources.audit(seed, client, state_dir / 'no-statics')
        donors_for_tyres, _ = tyres.donor_library(audit)
        means = tyres.compound_means(donors_for_tyres)
        tyre_inputs = {}
        for source_row in audit['sources']:
            choices = []
            for compound in tyres.LABELS:
                donor = source_row if compound == 'stock' else tyres.compound_donor(source_row, compound, donors_for_tyres, means)
                choices.append({**{k: donor.get(k) for k in tyres.DONOR_FIELDS}, 'gripBase': {k: donor.get('gripBase', {}).get(k) for k in ('model', 'axle')}})
            tyre_inputs.setdefault(source_row['model'], []).append(choices)
        inputs['tyres'] = {m: digest(json.dumps(rows, sort_keys=True).encode()) for m, rows in tyre_inputs.items()}
    else:
        inputs['tyres'] = old_inputs.get('tyres', {})
    changed.update(m for m, h in inputs['tyres'].items() if h != old_inputs.get('tyres', {}).get(m))
    # Preserve the existing tested-pair dependency when generating a subset.
    recipes = json.loads((ROOT / 'tools/engine_swaps/recipes.json').read_text())['recipes']
    for recipe in recipes:
        pair = {recipe['recipient'], recipe['donor']}
        if pair & (changed | removed):
            changed.update(pair & set(cars))
    changed &= set(cars)
    return {'beammp': beammp, 'archive': archive, 'state_dir': state_dir, 'registry': registry,
            'inputs': inputs, 'previous': previous, 'cars': cars,
            'changed': sorted(changed), 'removed': sorted(removed)}


def merge_catalogue(old, new, affected, index):
    out = {**old, **{k: v for k, v in new.items() if k not in ('parts', 'stocks', 'models', 'swaps')}}
    if index == 0:
        out['parts'] = {k: v for k, v in old.get('parts', {}).items() if v.get('model') not in affected}
        out['parts'].update(new.get('parts', {}))
        out['stocks'] = {k: v for k, v in old.get('stocks', {}).items() if k.split('/')[0] not in affected}
        out['stocks'].update(new.get('stocks', {}))
        out['sourceCars'] = len({k.split('/')[0] for k in out['stocks']})
    else:
        out['models'] = {k: v for k, v in old.get('models', {}).items() if k not in affected}
        out['models'].update(new.get('models', {}))
        if index == 1:
            out['swaps'] = {k: v for k, v in old.get('swaps', {}).items() if v.get('recipient') not in affected}
            out['swaps'].update(new.get('swaps', {}))
        if 'donors' in new:
            out['donors'] = new['donors']
    return canonical(out)


def validate(root):
    """Read generated JSON/JBeam and reject duplicate or missing part identities."""
    from jbeam_json import loads
    seen = set()
    for p in sorted((root / 'vehicles').glob('*/raceprep/rp_*.jbeam')):
        try:
            data = loads(p.read_text())
        except ValueError as e:
            raise ValueError(f'{p.name}: {e}') from e
        if not isinstance(data, dict) or not data:
            raise ValueError(f'Empty/invalid generated part: {p.name}')
        for name in data:
            if name in seen:
                raise ValueError(f'Duplicate generated part: {name}')
            seen.add(name)
    for rel in CATALOGUES:
        if not isinstance(json.loads((root / rel).read_text()), dict):
            raise ValueError(f'Invalid catalogue: {rel}')
    upgrades = json.loads((root / CATALOGUES[0]).read_text())
    missing = set(upgrades.get('parts', {})) - seen
    for rel in CATALOGUES[2:]:
        catalog = json.loads((root / rel).read_text())
        for row in catalog.get('models', {}).values():
            missing.update(o['part'] for o in row.get('options', []) if o.get('part') and o['part'] not in seen)
    if missing:
        raise ValueError('Catalogue references missing parts: ' + ', '.join(sorted(missing)[:8]))
    return len(seen)


def seed(beammp, donors=None):
    """Record the installed expansion ZIP as current for the cars it already has
    parts for, without generating anything (a live server deploy installs a
    ZIP built with measured calibration data; regenerating it at the next start
    would replace that work with derived values). A car without parts in the
    ZIP stays unrecorded, so the next start still builds it."""
    state_dir = Path(beammp).resolve() / 'Resources/Server/RacePrep/updater'
    state_dir.mkdir(parents=True, exist_ok=True)
    plan = inspect(beammp, donors)
    with zipfile.ZipFile(plan['archive']) as z:
        names = [n for n in z.namelist() if not n.endswith('/')]
        with_parts = {n.split('/')[1] for n in names if n.startswith('vehicles/') and '/raceprep/rp_' in n}
        outputs = {n: digest(z.read(n)) for n in sorted(names) if n in CATALOGUES or
                   (n.startswith('vehicles/') and Path(n).name.startswith('rp_') and Path(n).suffix in ('.jbeam', '.json'))}
    inputs = dict(plan['inputs'])
    inputs['cars'] = {m: r for m, r in inputs['cars'].items() if m in with_parts}
    inputs['tyres'] = {m: h for m, h in inputs.get('tyres', {}).items() if m in with_parts}
    manifest = {'version': 1, 'inputs': inputs, 'outputs': outputs}
    tmp = state_dir / 'generation-state.json.tmp'
    tmp.write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
    os.replace(tmp, state_dir / 'generation-state.json')
    missing = sorted(set(plan['cars']) - with_parts)
    return {'status': 'seeded', 'cars': len(inputs['cars']), 'withoutParts': missing}


def update(beammp, verbose=False, donors=None, check=False, server_session=False):
    state_dir = Path(beammp).resolve() / 'Resources/Server/RacePrep/updater'
    state_dir.mkdir(parents=True, exist_ok=True)
    release_work = Path(beammp).resolve() / '.raceprep-update'
    if (release_work / 'request.lock').exists() or (release_work / 'ready.json').exists():
        raise RuntimeError('A release update is pending/running; stop BeamMP and use start-bjrme-server before generating')
    if (state_dir / 'server-session.lock').exists() and not server_session:
        raise RuntimeError('Server launcher is active; defer generation until it stops')
    # Directory lock is atomic on Windows/Linux; no unsafe stale-lock takeover.
    lock = state_dir / 'generation.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        raise RuntimeError(f'Another generator is running, or a previous run was interrupted. Check processes before removing {lock}')
    try:
        plan = inspect(beammp, donors)
        changed, removed = plan['changed'], plan['removed']
        print(f"[BJR:ME] {len(plan['cars'])} Automation vehicles; donors {plan['registry']['counts']}; {len(changed)} require generation", flush=True)
        result = {'status': 'check' if check else 'up-to-date', 'newCars': changed, 'removedCars': removed}
        if check or not (changed or removed):
            return result
        affected = set(changed + removed)
        with tempfile.TemporaryDirectory(prefix='generation-', dir=state_dir) as tmp:
            tmp = Path(tmp)
            shipped, generated, resources = tmp / 'shipped', tmp / 'generated', tmp / 'resources'
            resources.mkdir()
            with zipfile.ZipFile(plan['archive']) as z:
                for name in z.namelist():
                    if name.startswith(('/', '\\')) or '..' in Path(name.replace('\\', '/')).parts:
                        raise ValueError('Unsafe expansion ZIP member: ' + name)
                z.extractall(shipped)
            for model in changed:
                source = Path(plan['cars'][model]['archive'])
                shutil.copyfile(source, resources / source.name)
            # Some archives contain multiple models: all of them are regenerated.
            batch_models = set(fleet.discover(resources))
            affected |= batch_models
            if changed:
                from generate_upgrades import run
                run(resources, tmp / 'no-statics', generated, donors=donors, tyre_resources=plan['archive'].parent)
            for model in affected:
                folder = shipped / 'vehicles' / model / 'raceprep'
                if folder.is_dir():
                    for p in folder.glob('rp_*'):
                        if p.suffix in ('.jbeam', '.json'):
                            p.unlink()
            for source in (generated / 'vehicles').glob('*/raceprep/rp_*'):
                if source.suffix not in ('.jbeam', '.json') or source.relative_to(generated).as_posix() in CATALOGUES:
                    continue
                target = shipped / source.relative_to(generated)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
            for index, rel in enumerate(CATALOGUES):
                target, fresh = shipped / rel, generated / rel
                # A full affected fleet replaces the complete generated index,
                # including a malformed old catalogue that needs repair.
                old = (json.loads(target.read_text()) if target.exists() else {}) if set(plan['cars']) - affected else {}
                new = json.loads(fresh.read_text()) if fresh.exists() else {}
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(json.dumps(merge_catalogue(old, new, affected, index), sort_keys=True, indent=2) + '\n')
            count = validate(shipped)
            outputs = {p.relative_to(shipped).as_posix(): digest(p.read_bytes())
                       for p in sorted(shipped.rglob('*')) if p.is_file() and
                       (p.relative_to(shipped).as_posix() in CATALOGUES or
                        (p.name.startswith('rp_') and p.suffix in ('.jbeam', '.json')))}
            manifest = {'version': 1, 'inputs': plan['inputs'], 'outputs': outputs}
            state_tmp = tmp / 'state.json'
            state_tmp.write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
            write_zip(shipped, plan['archive'])
            os.replace(state_tmp, state_dir / 'generation-state.json')
            print(f'[BJR:ME] Validated {count} parts; client ZIP updated before server startup', flush=True)
            return {**result, 'status': 'updated', 'parts': count}
    finally:
        lock.rmdir()
