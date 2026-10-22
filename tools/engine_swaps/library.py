# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Approved engine library: real parts, conservative fit checks, original visuals.

Reads donor archives without mounting/editing them. The recipient's sound and
engine mesh stay installed, so builds need no donor mod or donor sound banks.
"""
import copy
import shutil
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import zipfile

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from runtime_paths import TOOLS
import fleet
import generate_upgrade_engines
from .catalogue import scan, uncomment, donor_archive
from .build_prototype import build
from .bay import fit, rotate
from . import fuel, native_intakes

APPROVED = TOOLS / 'engine_swaps/approved-lineup.json'


def defaults(row):
    """Numeric engine defaults; chassis settings and visual offsets stay put."""
    prefix = row['engineMember'].rsplit('/', 1)[0] + '/'
    pattern = r'\[\s*"(\$[^"\n]+)"\s*,\s*"range"\s*,\s*"[^"\n]*"\s*,\s*"[^"\n]*"\s*,\s*([-+\d.eE]+)'
    result = {}
    with zipfile.ZipFile(row['archive']) as archive:
        for name in archive.namelist():
            if name.startswith(prefix) and name.endswith('.jbeam'):
                for key, value in re.findall(pattern, uncomment(archive.read(name).decode())):
                    if 'Vis' not in key and not key.startswith('$EngineOffset'):
                        result[key] = float(value)
        pc = json.loads(archive.read(f'vehicles/{row["model"]}/{row["config"]}.pc'))
        for key in result:
            if isinstance(pc.get('vars', {}).get(key), (int, float)):
                result[key] = pc['vars'][key]
    return result


def incompatibility(recipient, donor):
    if recipient['enginePart'] == donor['enginePart']:
        return 'Already the original engine'
    fuel_error = fuel.compatibility(recipient, donor)
    if fuel_error:
        return fuel_error
    if donor['engineDevice'] == 'camsoEngine' and recipient['engineDevice'] != 'camsoEngine':
        return 'Automation engine runtime unavailable in this car'
    if donor['engineDevice'] not in ('camsoEngine', 'combustionEngine'):
        return 'Unsupported engine runtime'
    return fit(recipient, donor).get('reason')


def generate(resources, output, approved=APPROVED):
    output, resources = Path(output), Path(resources)
    selected = json.loads(Path(approved).read_text())
    if selected.get('version')!=1 or selected.get('engineMeshReplacement') is not False:
        raise ValueError('Unsupported engine lineup or mesh policy')
    cars = fleet.discover(resources)
    recipients = scan(resources, archives={Path(c['archive']) for c in cars.values()})
    donors = []
    for choice in selected['engines']:
        if choice.get('ownerSelected') is not True:
            raise ValueError(f'Engine donor has not been approved: {choice["model"]}')
        source = donor_archive(choice['archive'], resources)
        if source is None:
            print(f"engine conversions: donor {choice['model']} not installed ({Path(choice['archive']).name}); its engine is skipped", flush=True)
            continue
        with source.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != choice['archiveSha256']:
                raise ValueError(f'Engine donor changed; revalidate {choice["model"]}')
        found = scan(source.parent, archives=[source])
        match = [r for r in found['engines'] if r['model'] == choice['model'] and r['config'] == choice['config']]
        if len(match) != 1:
            raise ValueError(f'Cannot read donor {choice["model"]}: {found["errors"]}')
        donors.append({**match[0], 'layout': choice['layout'], 'donorID': choice.get('donorID', choice['model'])})
    catalog = {'version': 1, 'models': {}, 'donors': [
        {k: d[k] for k in ('model', 'layout', 'litres', 'infoHP', 'fuel')} for d in donors]}
    engine_path = output / 'lua/common/raceprep/engine-parts.json'
    engine_catalog = json.loads(engine_path.read_text()) if engine_path.exists() else {'models': {}}
    engine_catalog['swaps'] = {}
    count = 0
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        donor_resources = temp / 'donors'
        donor_resources.mkdir()
        for d in donors:
            if d['engineDevice'] == 'camsoEngine':
                path = donor_resources / (d['model'] + '.zip')
                if not path.exists():
                    shutil.copyfile(d['archive'], path)
        donor_output = temp / 'donor-upgrades'
        generate_upgrade_engines.generate(donor_resources, donor_output, temp / 'no-statics')
        donor_upgrades = json.loads((donor_output / 'lua/common/raceprep/engine-parts.json').read_text())['models']
        for r in sorted(recipients['engines'], key=lambda r: (r['model'], r['config'])):
            model = r['model']
            if model not in cars or r['config'] != cars[model]['config']:
                continue
            original_defaults = defaults(r)
            model_info = {'stockEngine': r['enginePart'], 'stockStructure': r['structurePart'],
                          'stockDefaults': original_defaults, 'engineBay': r['engineBay'], 'options': []}
            catalog['models'][model] = model_info
            folder = output / 'vehicles' / model / 'raceprep'
            for d in donors:
                item = {k: d[k] for k in ('model', 'layout', 'litres', 'infoHP', 'fuel')}
                item['reason'] = incompatibility(r, d)
                item['fit'] = {k:v for k,v in fit(r,d).items() if k not in
                               ('nodes', 'positionOffsetXYZ', 'donorCentreXYZ', 'recipientCentreXYZ')}
                model_info['options'].append(item)
                if item['reason']:
                    continue
                ident = 'rp_swap_' + hashlib.sha256((model + '/' + d.get('donorID', d['model'])).encode()).hexdigest()[:12]
                label = f'{d["layout"]}: {d["litres"]:.2f} L, {d["infoHP"]} hp (export), {d["title"]}'
                info = copy.deepcopy(donor_upgrades.get(d['model']))
                # A native combustionEngine keeps its real native upgrades;
                # it must never receive the recipient camsoEngine's effects.
                upgrade_renames = {}
                generated = None
                if info:
                    generated = json.loads((donor_output / 'vehicles' / d['model'] / 'raceprep/rp_engine_parts.jbeam').read_text())
                    # Generated donor upgrades are reused across recipients.
                    # Namespace synthetic parts AND slots per conversion, as we
                    # already do for the original donor engine's native parts.
                    tokens = set(re.findall(r'rp_engine_[A-Za-z0-9_]+', json.dumps([generated, info])))
                    upgrade_renames = {name: ident + '_' + name for name in tokens}
                    info['hub'] = upgrade_renames.get(info['hub'], info['hub'])
                    info['archive']=d['archive']
                    info['hubSlot'] = ident + '_engine_upgrades'
                    with zipfile.ZipFile(d['archive']) as archive:
                        stock = json.loads(archive.read(f'vehicles/{d["model"]}/{d["config"]}.pc'))
                    for name in stock['parts'].values():
                        if name in info['parts']:
                            info['parts'][name]['effect'] = {}
                tank = fuel.generate(r, d, ident)
                staging = temp / ident
                proof = build({'engines': [r, d]}, model, d['model'], staging,
                              ident=ident, label=label, keep_audio=True,
                              engine_hub=info and info['hub'], hub_slot=info and info['hubSlot'],namespace=True,fuel_conversion=tank is not None)
                folder.mkdir(parents=True, exist_ok=True)
                if tank:
                    (folder / (ident+'_fuel.jbeam')).write_text(tank['text'])
                    item['fuelTank'] = {k:v for k,v in tank.items() if k!='text'}
                    model_info['stockFuelTank'] = tank['stockPart']
                for source in sorted((staging / 'vehicles' / model / 'rp_swap').glob('*.jbeam')):
                    (folder / f'{ident}_{source.name}').write_bytes(source.read_bytes())
                if info:
                    proof['partRenames'].update(upgrade_renames)
                    def remap(value):
                        if isinstance(value,dict):return {proof['partRenames'].get(k,k):remap(v) for k,v in value.items()}
                        if isinstance(value,list):return [remap(v) for v in value]
                        return proof['partRenames'].get(value,value) if isinstance(value,str) else value
                    generated,info=remap(generated),remap(info)
                    generated[info['hub']]['slotType'] = info['hubSlot']
                    offset = proof['positionOffsetXYZ']
                    for part in generated.values():
                        for node in part.get('nodes', [])[1:]:
                            if not isinstance(node, list):
                                continue
                            coordinates=[]
                            for axis in range(3):
                                expr = node[axis + 1]
                                m = re.fullmatch(r'\$=([-+\d.eE]+)\+\(\$EngineOffset'+'XYZ'[axis]+r' or 0\)', str(expr))
                                if not m:
                                    raise ValueError('Unsupported engine upgrade mass coordinate')
                                coordinates.append(float(m[1]))
                            coordinates = rotate(coordinates, proof['rotationDegrees'])
                            for axis in range(3):
                                node[axis + 1] = '$=' + str(coordinates[axis] + offset[axis]) + '+($EngineOffset'+'XYZ'[axis]+' or 0)'
                    (folder / f'{ident}_upgrades.jbeam').write_text(json.dumps(generated, indent=2) + '\n')
                native_additions = native_intakes.generate(d, ident, proof['partRenames'], defaults(d).get('$revLimitRPM'))
                if native_additions:
                    (folder / (ident+'_native_intakes.jbeam')).write_text(json.dumps(native_additions,indent=2)+'\n')
                engine_catalog['swaps'][proof['part']] = {'recipient': model, 'donor': d['model'],
                    'runtime': d['engineDevice'], 'engineInfo': info}
                item.update({'part': proof['part'], 'structure': proof['structure'], 'title': label,
                    'engineKG': proof['donorBlockKG'], 'massDeltaKG': proof['massDeltaKG'],
                    'resetVars': {**original_defaults, **defaults(d)}, 'runtime': d['engineDevice']})
                count += 1
    engine_path.parent.mkdir(parents=True, exist_ok=True)
    engine_path.write_text(json.dumps(engine_catalog, indent=2) + '\n')
    # Existing build pathspec covers this catalogue and the generated JBeam.
    destination = output / 'vehicles/rp_engine_swaps/raceprep/rp_swap_library.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(catalog, indent=2) + '\n')
    return {'parts': count, 'models': len(catalog['models']), 'errors': recipients['errors']}
