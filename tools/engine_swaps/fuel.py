# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Clone the recipient tank with the donor export's actual fuel properties.

No invented fuel constants: unsupported/missing export data keeps a swap blocked.
Capacity, nodes, rupture behaviour and the litre slider remain the recipient's.
"""
from functools import lru_cache
import json
import re
import zipfile
from .catalogue import part, uncomment, number

@lru_cache(maxsize=None)
def tank(archive, model, config):
    with zipfile.ZipFile(archive) as z:
        pc = json.loads(z.read(f'vehicles/{model}/{config}.pc'))
        chosen = pc.get('parts', {}).get('Camso_FuelTank')
        candidates = []
        for member in z.namelist():
            if not member.startswith(f'vehicles/{model}/') or not member.endswith('.jbeam'):
                continue
            text = uncomment(z.read(member).decode())
            for match in re.finditer(r'"([^"\n]+)"\s*:\s*\{\s*"information"\s*:', text):
                obj = part(text, match[1])
                if re.search(r'"slotType"\s*:\s*"Camso_FuelTank"', obj) and re.search(r'"mainTank"\s*:\s*\{', obj):
                    candidates.append((match[1], obj))
        if chosen:
            candidates = [c for c in candidates if c[0] == chosen]
        if len(candidates) != 1:
            raise ValueError('Cannot identify original fuel tank for '+model)
        name, source = candidates[0]
        data = part(source, 'mainTank')
        energy = re.search(r'"energyType"\s*:\s*"([^"\n]+)"', data)
        density, liquid = number(data, 'energyDensity'), number(data, 'fuelLiquidDensity')
        if not energy or not density or density <= 0 or not liquid or liquid <= 0:
            raise ValueError('Missing explicit donor fuel properties for '+model)
        return {'part': name, 'source': source, 'energyType': energy[1],
                'energyDensity': density, 'fuelLiquidDensity': liquid}

def spec(row):
    return tank(row['archive'], row['model'], row['config'])

def compatibility(recipient, donor):
    if recipient['fuel'] == donor['fuel']:
        return None
    try:
        spec(recipient); spec(donor)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as e:
        return 'Fuel conversion unavailable: '+str(e)
    return None

def generate(recipient, donor, ident):
    if recipient['fuel'] == donor['fuel']:
        return None
    original, fuel = spec(recipient), spec(donor)
    source = original['source']
    for key in ('energyType', 'energyDensity', 'fuelLiquidDensity'):
        pattern = r'("'+key+r'"\s*:\s*)("[^"\n]*"|[-+\d.eE]+)'
        source, count = re.subn(pattern, lambda m: m[1]+json.dumps(fuel[key]), source)
        if count != 1:
            raise ValueError('Ambiguous tank fuel field '+key)
    source = re.sub(r'("name"\s*:\s*")[^"\n]*',
                    lambda m: m[1]+'Race Prep '+donor['fuel']+' fuel tank (original capacity)', source, count=1)
    name = ident+'_fuel_tank'
    return {'part': name, 'stockPart': original['part'], 'slot': 'Camso_FuelTank',
            'fuel': donor['fuel'], 'energyType': fuel['energyType'],
            'text': '\n'.join(line.rstrip() for line in ('{'+json.dumps(name)+':'+source+'}').splitlines())+'\n'}
