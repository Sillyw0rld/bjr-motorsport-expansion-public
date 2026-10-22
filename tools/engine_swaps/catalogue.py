#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Read-only Automation engine inventory, with source and fit provenance."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zipfile

try:
    from .legacy_car import read as read_legacy
    from .bay import measure as measure_bay, verify_frame
except ImportError:  # standalone catalogue.py / historical prototype tools
    from legacy_car import read as read_legacy
    from bay import measure as measure_bay, verify_frame


def car_table(raw):
    """Automation's version-1 tagged tables; no pickle, eval or game execution."""
    if raw[:2] != b'\x01T':
        return read_legacy(raw)
    pos = 1
    def read(depth=0):
        nonlocal pos
        if depth > 60 or pos >= len(raw):
            raise ValueError('invalid .car depth/length')
        tag = raw[pos:pos+1]; pos += 1
        if tag == b'S':
            n = struct.unpack_from('<I', raw, pos)[0]; pos += 4
            if n > len(raw)-pos:
                raise ValueError('invalid .car string')
            value = raw[pos:pos+n]; pos += n
            if value.startswith(b'\x01T'):
                return car_table(value)
            return value.decode('utf8', 'replace')
        if tag == b'N':
            value = struct.unpack_from('<d', raw, pos)[0]; pos += 8
            if not math.isfinite(value):
                raise ValueError('nonfinite .car number')
            return value
        if tag == b'T':
            a, b = struct.unpack_from('<II', raw, pos); pos += 8
            if a+b > 500000:
                raise ValueError('oversized .car table')
            result = {}
            for _ in range(a+b):
                key = read(depth+1); result[key] = read(depth+1)
            return result
        if tag == b'B':
            value = raw[pos]; pos += 1
            return bool(value)
        if tag in (b'0', b'1'):
            return tag == b'1'
        raise ValueError('unknown .car tag ' + repr(tag))
    result = read()
    if pos != len(raw):
        raise ValueError('trailing .car data')
    return result


def uncomment(text):
    return re.sub(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else '', text, flags=re.S)


def part(text, name):
    text = uncomment(text)
    match = re.search(r'"'+re.escape(name)+r'"\s*:\s*\{', text)
    if not match:
        raise ValueError('part absent: ' + name)
    start = text.index('{', match.start()); depth = 0; quoted = escaped = False
    for i in range(start, len(text)):
        c = text[i]
        if quoted:
            if escaped: escaped = False
            elif c == '\\': escaped = True
            elif c == '"': quoted = False
        elif c == '"': quoted = True
        elif c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if not depth: return text[start:i+1]
    raise ValueError('unterminated part: ' + name)


def number(text, key):
    match = re.search(r'"'+re.escape(key)+r'"\s*:\s*([-+\d.eE]+)', text)
    return float(match[1]) if match else None


def geometry(text):
    weight = None; nodes = []
    # Scope to nodes: unrelated beam/mesh numbers must not affect this audit.
    section = text.split('"nodes"', 1)[1].split('"beams"', 1)[0]
    for match in re.finditer(r'"nodeWeight"\s*:\s*([-+\d.eE]+)|\["(engine[0-7])",\s*([-+\d.eE]+),\s*([-+\d.eE]+),\s*([-+\d.eE]+)', section):
        if match[1] is not None: weight = float(match[1])
        elif weight is not None:
            nodes.append({'id':match[2], 'pos':list(map(float, match.group(3,4,5))), 'mass':weight})
    if len(nodes) != 8 or len({n['id'] for n in nodes}) != 8:
        raise ValueError('engine block does not have eight identified nodes')
    low = [min(n['pos'][i] for n in nodes) for i in range(3)]
    high = [max(n['pos'][i] for n in nodes) for i in range(3)]
    return {'nodes':nodes, 'massKG':sum(n['mass'] for n in nodes),
            'low':low, 'high':high, 'sizeXYZ':[b-a for a,b in zip(low,high)]}


def scan(folder, archives=None):
    records, errors = [], []
    archives = sorted(folder.glob('*.zip') if archives is None else archives)
    for archive in archives:
        try:
            with zipfile.ZipFile(archive) as z:
                names = z.namelist()
                cars = [n for n in names if n.endswith('.car') and n.startswith('vehicles/')]
                for car_name in cars:
                    try:
                        model = car_name.split('/')[1]; design = car_table(z.read(car_name))
                        family, variant = design.get('Family', {}), design.get('Variant', {})
                        block = family.get('BlockConfig', '')
                        cyl_match = re.search(r'(?:Inl|V|Box(?:er)?|Flat)(\d+)', block)
                        cylinders = int(cyl_match[1]) if cyl_match else None
                        prefix = 'I' if 'Inl' in block else 'V' if '_V' in block else 'B' if 'Box' in block else '?'
                        configs = [n for n in names if n.startswith('vehicles/'+model+'/') and n.count('/') == 2 and n.endswith('.pc')]
                        for config_name in configs:
                            pc = json.loads(z.read(config_name)); engine = pc.get('parts', {}).get('Camso_Engine')
                            if not engine: continue
                            member = next(n for n in names if n.startswith('vehicles/'+model+'/') and n.endswith('.jbeam') and re.search(r'"'+re.escape(engine)+r'"\s*:', z.read(n).decode('utf8','replace')))
                            text = part(z.read(member).decode('utf8','replace'), engine)
                            device = re.search(r'\["(camsoEngine|combustionEngine)",\s*"mainEngine"', text)
                            config = Path(config_name).stem
                            info = json.loads(z.read(f'vehicles/{model}/info_{config}.json'))
                            structure = pc.get('parts', {}).get('Camso_engine_structure')
                            if not structure:
                                m = re.search(r'\["Camso_engine_structure",\s*"([^"]+)"',text); structure = m[1] if m else None
                            structure_member = next(n for n in names if n.startswith('vehicles/'+model+'/') and n.endswith('.jbeam') and re.search(r'"'+re.escape(structure)+r'"\s*:', z.read(n).decode('utf8','replace')))
                            shape = geometry(part(z.read(structure_member).decode('utf8','replace'), structure))
                            bay = measure_bay(design)
                            if bay.get('available'):
                                wheel_texts = []
                                for slot in ('Camso_wheels_front', 'Camso_wheels_rear'):
                                    chosen = pc.get('parts', {}).get(slot)
                                    wheel_member = next((n for n in names if n.endswith('.jbeam') and
                                        n.startswith('vehicles/'+model+'/') and
                                        chosen and re.search(r'"'+re.escape(chosen)+r'"\s*:', z.read(n).decode('utf8','replace'))), None)
                                    wheel_texts.append(part(z.read(wheel_member).decode('utf8','replace'), chosen) if wheel_member else '')
                                bay = verify_frame(bay, design, *wheel_texts)
                            bore, stroke = variant.get('Bore'), variant.get('Stroke')
                            rows = re.findall(r'\[\s*99(?:\.0)?\s*,\s*([-+\d.eE]+),\s*([-+\d.eE]+),\s*([-+\d.eE]+),\s*([-+\d.eE]+)\]', text)
                            setup = variant.get('AspirationSetup','')
                            record = {'model':model,'config':config,'archive':str(archive),'carMember':car_name,
                                'carSha256':hashlib.sha256(z.read(car_name)).hexdigest(),
                                'enginePart':engine,'engineMember':member,'engineSha256':hashlib.sha256(z.read(member)).hexdigest(),
                                'engineDevice':device[1] if device else None,
                                'structurePart':structure,'structureMember':structure_member,
                                'title':info.get('Configuration', model),'familyName':family.get('Name'),'variantName':variant.get('Name'),
                                'block':block,'layout':prefix+str(cylinders),'cylinders':cylinders,
                                'litres':math.pi/4*bore*bore*stroke*cylinders/1e6 if bore and stroke and cylinders else None,
                                'aspiration':variant.get('AspirationType'),'aspirationSetup':setup,
                                'infoHP':info.get('Power'),'fuel':info.get('Fuel Type'),'drive':info.get('Drivetrain'),
                                'inertia':number(text,'inertia'),'friction':number(text,'friction'),'dynamicFriction':number(text,'dynamicFriction'),
                                'engineGeometry':shape,'engineBay':bay,
                                'raw99PeakHP':max((float(t)*float(r)/7127 for r,t,_,_ in rows),default=None)}
                            records.append(record)
                    except (ValueError, KeyError, StopIteration, TypeError, struct.error) as e:
                        errors.append({'archive':archive.name,'car':car_name,'error':str(e)})
        except zipfile.BadZipFile:
            errors.append({'archive':archive.name,'error':'invalid zip'})
    return {'archivesScanned':len(archives),'engines':records,'errors':errors}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mods',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();data=scan(a.mods);a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(data,indent=2)+'\n')
    print('Archives:',data['archivesScanned'],'engines:',len(data['engines']),'errors:',len(data['errors']))
    groups = {}
    for r in data['engines']:
        key=r['layout']+' '+str(r['aspiration'])+' '+str(r['aspirationSetup']);groups.setdefault(key,[]).append(r)
    for key,rows in sorted(groups.items()):
        rows=sorted(rows,key=lambda r:r['infoHP'] or 1e9)
        print(key,len(rows),'; '.join(f"{r['model']} {r['infoHP']}hp {r['fuel']}" for r in rows[:8]))


if __name__=='__main__':main()

def donor_archive(name, resources=None):
    """a donor car zip by file name: RACEPREP_DONORS folders (os.pathsep separated), then the server's car folder; None if absent"""
    import os
    p = Path(name)
    folders = [f for f in os.environ.get('RACEPREP_DONORS', '').split(os.pathsep) if f]
    for cand in ([p] if p.is_absolute() else []) + [Path(f) / p.name for f in folders] + [
            Path(resources or os.environ.get('RACEPREP_RESOURCES', 'Resources/Client')) / p.name]:
        if str(cand.parent) not in ('', '.') and cand.is_file():
            return cand
    return None
