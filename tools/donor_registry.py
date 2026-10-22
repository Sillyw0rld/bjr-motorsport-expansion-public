# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""One source registry for bundled and administrator-supplied Automation donors."""
import hashlib
import json
import math
import zipfile
from pathlib import Path
from engine_swaps.catalogue import scan
import fleet

from runtime_paths import ROOT


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identity(source, model):
    with zipfile.ZipFile(source) as z:
        return sha(json.dumps([(n, sha(z.read(n))) for n in sorted(z.namelist())
                              if n.startswith(f'vehicles/{model}/') and
                              Path(n).suffix in {'.car', '.pc', '.jbeam', '.json'}]).encode())


def source_row(path, role):
    try:
        with zipfile.ZipFile(path) as z:
            for n in z.namelist():
                if n.startswith(('/', '\\')) or '..' in Path(n.replace('\\', '/')).parts:
                    raise ValueError('unsafe archive member ' + n)
            if z.testzip():
                raise ValueError('corrupted ZIP member')
        result = scan(path.parent, archives=[path])
        cars = fleet.discover(path.parent, archives=[path])
        rows = [r for r in result['engines'] if r['model'] in cars and r['config'] == cars[r['model']]['config']]
        # fleet selection is reused, but never allow another archive in the
        # same donor folder to silently choose this export's configuration.
        if not rows or result['errors']:
            raise ValueError(f"incomplete/unsupported Automation export: {result['errors']}")
        out = []
        for r in rows:
            if not isinstance(r.get('inertia'), (int, float)) or not math.isfinite(r['inertia']) or r['inertia'] <= 0:
                raise ValueError(f"{r['model']}: missing engine inertia")
            if role == 'drivetrains':
                from drivetrain_conversions.library import inspect_recipient
                rec = inspect_recipient(r['model'], {'archive': str(path), 'config': r['config'], 'pc': cars[r['model']]['pc']})
                layout = rec['stockDrive']
                if layout not in ('FWD', 'RWD', 'AWD') or not rec['stockTransmission']:
                    raise ValueError(f"{r['model']}: unsupported powertrain graph")
            else:
                layout = r['layout'] + ' ' + str(r.get('aspiration') or '')
            with zipfile.ZipFile(path) as z:
                members = {n: sha(z.read(n)) for n in sorted(z.namelist())
                           if n.startswith(f"vehicles/{r['model']}/") and n.endswith('.jbeam')}
            out.append({'model': r['model'], 'config': r['config'], 'layout': layout.strip(),
                        'archive': str(path.resolve()), 'archiveSha256': sha(path.read_bytes()),
                        'carMember': r['carMember'], 'carSha256': r['carSha256'],
                        'membersSha256': members, 'ownerSelected': True, 'origin': 'custom',
                        'donorID': 'donor_' + sha(f"{r['model']}/{r['config']}".encode())[:16]})
        return out
    except Exception as e:
        raise ValueError(f'{path.name}: {e}') from e


def load(root=None):
    """Bundled (default) and the administrator's own (custom) donors.

    The Play edition ships default donors; the Custom edition has no default
    folder at all and uses only the administrator's donors. A default folder
    that exists but is incomplete is an error (a damaged install)."""
    root = Path(root or ROOT / 'donors')
    result = {'engines': [], 'drivetrains': [], 'counts': {'default': 0, 'custom': 0}}
    bundled = (root / 'default').is_dir()
    result['edition'] = 'play' if bundled else 'custom'
    for role, key in [('engines', 'engines'), ('drivetrains', 'donors')]:
        seen = {}
        manifest = root / 'default' / (role + '.json')
        if bundled and not manifest.is_file():
            raise ValueError(f'Missing bundled donor manifest: {manifest}')
        selected = json.loads(manifest.read_text()) if bundled else {key: []}
        for r in selected[key]:
            path = root / 'default' / role / Path(r['archive']).name
            if not path.is_file() or sha(path.read_bytes()) != r['archiveSha256']:
                raise ValueError(f'Missing or changed bundled donor: {path.name}')
            row = {**r, 'archive': str(path.resolve()), 'origin': 'default'}
            seen[(r['model'], r['config'])] = identity(path, r['model'])
            result[role].append(row)
            result['counts']['default'] += 1
        folders = [root / 'custom' / role]
        # Legacy search roots remain in donor_archive(); only explicit custom
        # role folders opt a source into automatic import.
        for path in sorted({p.resolve() for folder in folders for p in folder.glob('*.zip')}):
            for row in source_row(path, role):
                key_id = row['model'], row['config']
                content = identity(path, row['model'])
                if key_id in seen:
                    if seen[key_id] != content:
                        raise ValueError(f'Conflicting donor identity {key_id}: {path.name}')
                    continue
                if any(r['model'] == row['model'] for r in result[role]):
                    raise ValueError(f'{path.name}: multiple configurations for donor model {row["model"]} are not supported')
                seen[key_id] = content
                result[role].append(row)
                result['counts']['custom'] += 1
    return result


def manifests(registry, folder):
    folder = Path(folder)
    engine = folder / 'engines.json'
    engine.write_text(json.dumps({'version': 1, 'engineMeshReplacement': False, 'engines': registry['engines']}))
    drivetrain = folder / 'drivetrains.json'
    drivetrain.write_text(json.dumps({'version': 1, 'donors': drivetrain_set(registry)}))
    return engine, drivetrain


def drivetrain_set(registry):
    """The FWD / RWD / AWD set drivetrain conversions are built from: the bundled
    one, or (Custom edition, no bundled donors) the administrator's own when
    they supplied exactly one donor per layout. Empty = conversions off."""
    defaults = [r for r in registry['drivetrains'] if r['origin'] == 'default']
    if defaults:
        return defaults
    custom = [r for r in registry['drivetrains'] if r['origin'] == 'custom']
    layouts = sorted(r.get('layout') for r in custom)
    return custom if layouts == ['AWD', 'FWD', 'RWD'] else []


def generate_custom_drivetrains(registry, resources, output, scratch):
    """Reuse the existing trio builder for each additional donor, without tuning it.

    A custom target is compared to the same bundled stock-layout reference as
    the existing conversions. Unsupported mass ordering is reported, not fixed.
    """
    from drivetrain_conversions.library import generate
    import tempfile
    import shutil
    output = Path(output)
    rel = Path('vehicles/rp_drivetrain_conversions/raceprep/rp_drivetrain_library.json')
    catalog = json.loads((output / rel).read_text())
    defaults = [r for r in registry['drivetrains'] if r['origin'] == 'default']
    if not defaults:
        return  # Custom edition: the administrator's own set is the base set (drivetrain_set)
    for donor in registry['drivetrains']:
        if donor['origin'] != 'custom':
            continue
        lineup = [donor if r['layout'] == donor['layout'] else r for r in defaults]
        manifest = Path(scratch) / (donor['donorID'] + '.json')
        manifest.write_text(json.dumps({'version': 1, 'donors': lineup}))
        with tempfile.TemporaryDirectory(prefix='rp-custom-dt-') as tmp:
            generate(resources, tmp, manifest, strict=True, namespace=donor['donorID'], offered_layout=donor['layout'])
            generated = json.loads((Path(tmp) / rel).read_text())
            for model, entry in generated['models'].items():
                for option in entry['options']:
                    option['donorID'] = donor['donorID']
                    if option.get('title'):
                        option['title'] += ' — ' + donor['model'].replace('_', ' ')
                    catalog['models'][model]['options'].append(option)
            catalog['donors'].extend(r for r in generated['donors'] if r['model'] == donor['model'])
            for source in Path(tmp).rglob('*.jbeam'):
                target = output / source.relative_to(tmp)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
    (output / rel).write_text(json.dumps(catalog, indent=2) + '\n')
