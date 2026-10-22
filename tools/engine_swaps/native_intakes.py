# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Missing intake choices for native-runtime Automation donors.

Use native additive intake curves, based on this donor's own base torque.
The high-rpm 3/6% gains match existing Race Prep Sport/Race intake effects.
No recipient effects or runtime extension are applied to native engines.
"""
import json
import re
import zipfile
from .catalogue import part

def generate(donor, ident, renames, limit):
    if donor['engineDevice'] != 'combustionEngine':
        return {}
    with zipfile.ZipFile(donor['archive']) as z:
        main = part(z.read(donor['engineMember']).decode(), donor['enginePart'])
        slots = re.findall(r'\["(Camso_Intake_[^"\n]+)",\s*"([^"\n]+)"', main)
        if len(slots) != 1:
            return {}
        slot, stock = slots[0]
        objects = {}
        prefix = donor['engineMember'].rsplit('/',1)[0]+'/'
        for member in z.namelist():
            if member.startswith(prefix) and member.endswith('.jbeam'):
                text = z.read(member).decode()
                for name in re.findall(r'"([^"\n]+)"\s*:\s*\{\s*"information"\s*:',text):
                    obj = part(text,name)
                    if re.search(r'"slotType"\s*:\s*"'+re.escape(slot)+'"',obj):objects[name]=obj
        # Only fill genuinely absent upgrade options. Never rewrite donor ones.
        if stock not in objects or any('race' in n.lower() for n in objects):return {}
        curve = re.search(r'"torque"\s*:\s*\[(.*?)\]\s*,\s*"',main,re.S)
        if not curve:return {}
        points = [(float(r),float(t)) for r,t in re.findall(r'\[\s*([-+\d.eE]+)\s*,\s*([-+\d.eE]+)\s*\]',curve[1])]
        if not points or not limit:return {}
        output={}
        for level,gain in [('sport',.03),('race',.06)]:
            torque=[['rpm','torque']]+[[rpm,torque*gain*max(0,min(1,(rpm/limit-.30)/.40))]for rpm,torque in points]
            output[ident+'_intake_'+level]={'information':{'authors':'Sillyw0rld','name':level.title()+' intake'},
                'slotType':renames.get(slot,slot),'mainEngine':{'torqueModIntake':torque}}
        return output
