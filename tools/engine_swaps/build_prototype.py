#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Build one private, additional engine part. Never edits factory archives.

First physics prototype retains the recipient engine mesh and exhaust.
Automation bay fit is screened when metadata is valid; otherwise the historical
stock-block envelope is required. Full donor mesh/plumbing clearance is NOT claimed.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parent))
from catalogue import part, uncomment
from bay import fit


def stabilize_engine_beams(source, original_nodes, new_nodes):
    """Lighter block nodes need matching springs/dampers at the physics step.
    Scale only beams touching those nodes; retain gearbox/chassis beams and all
    damage strengths. Keep the settings local to each beam, not inherited by
    subsequent chassis rows in the JBeam table.
    """
    before = {n['id']: n['mass'] for n in original_nodes}
    ratios = {n['id']: min(1, n['mass']/before[n['id']]) for n in new_nodes}
    active = False
    settings = {}
    count = 0
    lines = []
    for line in source.splitlines(keepends=True):
        if re.search(r'"beams"\s*:', line):
            active = True
        row = re.match(r'(\s*\["([^\"]+)",\s*"([^\"]+)"\s*,?\s*\{)(.*?)(\}\]\s*,?\s*)$', line) if active else None
        if row:
            factor = min(ratios.get(row[2], 1), ratios.get(row[3], 1))
            if factor < 1:
                options = row[4]
                for key in ('beamSpring', 'beamDamp'):
                    found = re.search(r'"'+key+r'"\s*:\s*([-+\d.eE]+)', options)
                    value = float(found[1]) if found else settings.get(key)
                    if value is None:
                        raise ValueError('Missing numeric '+key+' for engine beam '+row[2]+'/'+row[3])
                    replacement = json.dumps(key)+':'+str(value*factor)
                    if found:
                        options = options[:found.start()]+replacement+options[found.end():]
                    else:
                        options = replacement+(', '+options if options.strip() else '')
                line = row[1]+options+row[5]
                count += 1
        elif active:
            for key, value in re.findall(r'"(beamSpring|beamDamp)"\s*:\s*([-+\d.eE]+)', line):
                settings[key] = float(value)
        lines.append(line)
    return ''.join(lines), {'beamsScaled': count, 'minimumMassRatio': min(ratios.values())}


def build(inventory, recipient, donor, output, *, ident=None, label=None, keep_audio=False,
          engine_hub=None, hub_slot=None, namespace=False, fuel_conversion=False):
    rows=inventory['engines']
    r=next(x for x in rows if x['model']==recipient)
    d=next(x for x in rows if x['model']==donor)
    rg,dg=r['engineGeometry'],d['engineGeometry']
    placement = fit(r, d)
    assert placement['accepted'], placement['reason']
    assert r["fuel"]==d["fuel"] or fuel_conversion, "Cross-fuel swaps require a generated matching tank"
    assert r['engineDevice']==d['engineDevice'] or (r['engineDevice']=='camsoEngine' and d['engineDevice']=='combustionEngine'), 'custom engine runtime is unavailable in recipient'
    root=output/'vehicles'/recipient;root.mkdir(parents=True,exist_ok=True)
    ident=ident or 'rp_swap_'+donor
    structure=ident+'_structure';engine=ident+'_engine'
    proofs={}
    with zipfile.ZipFile(r['archive']) as rz,zipfile.ZipFile(d['archive']) as dz:
        # Donor engine data, intake/ECU/internals/turbo and their actual stock
        # defaults. Keep the recipient's transmission, fuel system and body.
        prefix=d['engineMember'].rsplit('/',1)[0]+'/'
        renames={}
        if namespace:
            for name in dz.namelist():
                if name.startswith(prefix) and name.endswith('.jbeam'):
                    text=dz.read(name).decode()
                    for key in re.findall(r'"([^"\n]+)"\s*:\s*\{\s*"information"\s*:',text):
                        renames[key]=engine if key==d['enginePart'] else ident+'_'+key
                    for key in re.findall(r'"slotType"\s*:\s*"([^"\n]+)"',text):
                        if key!='Camso_Engine' and key not in renames:renames[key]=ident+'_'+key
        main=part(dz.read(d['engineMember']).decode(),d['enginePart'])
        donor_pc=json.loads(dz.read(f'vehicles/{donor}/{d["config"]}.pc'))
        for slot,chosen in donor_pc.get('parts',{}).items():
            if slot in ('Camso_engine_structure','Camso_Transmission') or not chosen:
                continue
            main=re.sub(r'(\["'+re.escape(slot)+r'",\s*")[^"]*',lambda m:m[1]+chosen,main)
        if keep_audio:
            recipient_engine=part(rz.read(r['engineMember']).decode(),r['enginePart'])
            for sound in ('soundConfig','soundConfigExhaust'):
                if not re.search(r'"'+sound+r'"\s*:\s*\{',main):
                    continue
                replacement=part(recipient_engine,sound)
                main=main.replace(part(main,sound),replacement,1)
        if engine_hub:
            main,n=re.subn(r'("slots"\s*:\s*\[\s*\[[^\]]*\])\s*,?',
                lambda m:m[1]+',\n'+json.dumps([hub_slot,engine_hub,'Engine upgrade slots'])+',',main,count=1)
            assert n==1,'engine slots absent'
        pc=json.loads(rz.read(f'vehicles/{recipient}/{r["config"]}.pc'))
        main=re.sub(r'(\["Camso_engine_structure",\s*")[^"]+',lambda m:m[1]+structure,main,count=1)
        main=re.sub(r'(\["Camso_Transmission",\s*")[^"]+',lambda m:m[1]+pc['parts']['Camso_Transmission'],main,count=1)
        main=re.sub(r'("name"\s*:\s*")[^"]+',lambda m:m[1]+(label or 'Prototype swap: '+d['title']+' engine'),main,count=1)
        uid=d['enginePart'].removeprefix('Camso_Engine_')
        for name in dz.namelist():
            if not name.startswith(prefix) or not name.endswith('.jbeam'):continue
            # part() extracts comment-free object text. Replacing that object
            # in the raw commented source silently failed, discarding ALL main
            # edits (recipient sound, upgrade hub and stock drivetrain links).
            # Normalize the generated copy first; original ZIPs stay untouched.
            data=dz.read(name);text=uncomment(data.decode('utf8'))
            if name==d['engineMember']:
                original=part(text,d['enginePart'])
                assert original in text, 'donor engine object could not be replaced'
                text=text.replace(original,main,1).replace('"'+d['enginePart']+'"','"'+engine+'"',1)
            if renames:
                text=re.sub(r'"([^"\n]+)"',lambda m:json.dumps(renames[m[1]]) if m[1] in renames else m[0],text)
            target=root/'rp_swap'/Path(name).name;target.parent.mkdir(exist_ok=True)
            target.write_text('\n'.join(line.rstrip() for line in text.splitlines())+'\n')
            proofs[name]=hashlib.sha256(data).hexdigest()
        # Replace engine block nodes, not body mass or gearbox nodes. Place
        # the donor block at the recipient block centre using its real size.
        source=part(rz.read(r['structureMember']).decode(),r['structurePart'])
        offset=placement['positionOffsetXYZ']
        for node in placement['nodes']:
            pos=node['pos']
            pattern=r'\["'+node['id']+r'",\s*[-+\d.eE]+,\s*[-+\d.eE]+,\s*[-+\d.eE]+\s*,?\s*\{'
            replacement='["'+node['id']+'", '+', '.join(f'{v:.9f}' for v in pos)+', {"nodeWeight":'+str(node['mass'])+','
            source,n=re.subn(pattern,lambda m:replacement,source,count=1)
            assert n==1,node['id']
        source, stability = stabilize_engine_beams(source, rg['nodes'], placement['nodes'])
        # The gearbox, exhaust, meshes and all chassis attachment IDs stay
        # those of the recipient. The mesh is explicitly a prototype limit.
        (root/'rp_swap/structure.jbeam').write_text('\n'.join(line.rstrip() for line in ('{'+json.dumps(structure)+':'+source+'}').splitlines())+'\n')
        baseline=copy.deepcopy(pc)
        pc['parts']['Camso_Engine']=engine
        pc['parts']['Camso_engine_structure']=structure
        # Defaults for the newly selected donor subtree are authoritative;
        # no donor transmission, AWD split or wheel parts are copied.
        config='rp_swap_evo20t' if ident=='rp_swap_hawk_evolution_viii' else ident
        (root/(config+'.pc')).write_text(json.dumps(pc,indent=2)+'\n')
        (root/'rp_swap_stock.pc').write_text(json.dumps(baseline,indent=2)+'\n')
    manifest={'prototype':True,'recipient':recipient,'donor':donor,'config':config,
              'part':engine,'structure':structure,'engineDevice':d['engineDevice'],
              'stockBlockKG':rg['massKG'],'donorBlockKG':dg['massKG'],'massDeltaKG':dg['massKG']-rg['massKG'],
              'recipientBlockSizeXYZ':rg['sizeXYZ'],'donorBlockSizeXYZ':dg['sizeXYZ'],'positionOffsetXYZ':offset,
              'rotationDegrees':placement['rotationDegrees'],
              'fit':{k:v for k,v in placement.items() if k!='nodes'},
              'recipientInertia':r['inertia'],'donorInertia':d['inertia'],'donorInfoHP':d['infoHP'],
              'sourceFiles':proofs,'driveUnchanged':r['drive'],
              'recipientAudioRetained':keep_audio,
              'engineBeamStability':stability,
              'partRenames':renames,
              'fitLimit':'Bay dimensional/XY screen or stock-block fallback. Stock engine mesh/exhaust retained; absolute Z, donor plumbing and full component clearance not validated.',
              'ratingLimit':'Prototype only; no PI acceptance or multiplayer validation.'}
    (output/'prototype-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inventory',type=Path,required=True);p.add_argument('--recipient',required=True)
    p.add_argument('--donor',required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    out=a.output.resolve()
    if '/BEAMMP/' in str(out):raise ValueError('prototype must not be installed in the server')
    print(json.dumps(build(json.loads(a.inventory.read_text()),a.recipient,a.donor,out),indent=2))


if __name__=='__main__':main()
