# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Read engine identity without changing source archives. Unknowns stay explicit."""
import json
import math
import re
import zipfile
from pathlib import Path
from engine_swaps.catalogue import car_table, part, uncomment


def automation(archive, model):
    with zipfile.ZipFile(archive) as z:
        names = sorted(n for n in z.namelist() if n.startswith('vehicles/'+model+'/') and n.endswith('.car'))
        if len(names) != 1:
            return {'metadataSource': 'fallback: missing or ambiguous .car'}
        try:
            data = car_table(z.read(names[0]))
            family, variant = data['Family'], data['Variant']
            block = family.get('BlockConfig', '')
            count = re.search(r'(?:Inl|V|Box(?:er)?|Flat)(\d+)', block)
            cylinders = int(count[1]) if count else None
            arrangement = 'I' if 'Inl' in block else 'B' if any(k in block for k in ('Box', 'Flat')) else 'V' if '_V' in block else None
            if not arrangement or not cylinders:
                return {'metadataSource': 'fallback: unreadable block layout'}
            litres = math.pi/4*variant['Bore']**2*variant['Stroke']*cylinders/1e6
            return {'layout': arrangement+str(cylinders), 'litres': litres,
                    'aspiration': variant.get('AspirationType'), 'metadataSource': names[0]}
        except (ValueError, KeyError, TypeError):
            return {'metadataSource': 'fallback: unreadable .car'}


def native(vehicles):
    out = {}
    for archive in sorted(Path(vehicles).glob('*.zip')):
        with zipfile.ZipFile(archive) as z:
            for member in z.namelist():
                if not member.endswith('.jbeam'):
                    continue
                source = uncomment(z.read(member).decode('utf-8-sig', errors='replace'))
                if not re.search(r'\[\s*"combustionEngine"\s*,', source):
                    continue
                for match in re.finditer(r'"([^"\n]+)"\s*:\s*\{\s*"information"\s*:', source):
                    text = part(source, match[1])
                    if not re.search(r'\[\s*"combustionEngine"\s*,', text):
                        continue
                    title = re.search(r'"name"\s*:\s*(?:\{\s*"txt"\s*:\s*)?"([^"]+)"', text)
                    title = title[1] if title else ''
                    layout = re.search(r'\b([IVBFWH])(\d+)\b', title)
                    size = re.search(r'(\d+(?:\.\d+)?)\s*(L\b|cc\b|CUI\b)', title, re.I)
                    row = {'native': True, 'stockEngine': match[1], 'parts': {},
                           'metadataSource': archive.name+':'+member, 'title': title}
                    if layout:
                        row['layout'] = layout[1].replace('F', 'B')+layout[2]
                    if size:
                        row['litres'] = float(size[1])*{'l': 1, 'cc': .001, 'cui': .016387064}[size[2].lower()]
                    out[match[1]] = row
    return out


def enrich(catalog, vehicles, donors):
    """Metadata-only refresh: preserve all existing parts, choices and sources."""
    logged = set()
    def record(key, info):
        if not info.get('layout') or not info.get('litres'):
            if key not in logged:
                print('engine potential fallback: '+key+' (layout/displacement unavailable)')
                logged.add(key)
    for model, info in catalog['models'].items():
        info.update(automation(info['archive'], model))
        record(info['stockEngine'], info)
    for name, swap in catalog.get('swaps', {}).items():
        info = swap.get('engineInfo')
        donor = swap['donor']
        if info is None:
            info = {'native': True, 'stockEngine': name, 'parts': {}}
            swap['engineInfo'] = info
        if donor in catalog['models']:
            meta = {k: catalog['models'][donor][k] for k in ('layout', 'litres', 'aspiration', 'metadataSource') if k in catalog['models'][donor]}
        else:
            source = donors[donor]
            meta = automation(source, donor)
        info.update(meta)
        record(donor, info)
    catalog['nativeEngines'] = native(vehicles)
    for key, info in catalog['nativeEngines'].items():
        record(key, info)
    return catalog
