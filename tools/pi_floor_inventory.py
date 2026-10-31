#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Census shipped drivable .pc configs; metadata is not a performance estimate."""
import argparse,json,sys,zipfile
from collections import Counter
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from plan_vanilla_validation import decode,VEHICLES
EXCLUDED={'simple_traffic','unicycle','testroller','roof_crush_tester','anticut','flail','large_tire','tsfb','spikestrip','engine_props'}
def inventory(root,seed):
 rated={(e['model'],e['config'].lower()) for e in seed['entries'].values()}
 rows=[];excluded=[];errors=[]
 for path in sorted(Path(root).glob('*.zip')):
  with zipfile.ZipFile(path) as z:
   names=set(z.namelist())
   for name in sorted(names):
    if not(name.startswith('vehicles/')and name.count('/')==2 and name.endswith('.pc')):continue
    _,model,file=name.split('/');config=file[:-3]
    if model in EXCLUDED:
     excluded.append({'model':model,'config':config,'reason':'Owner-excluded model'});continue
    try:
     info=decode(z.read(f'vehicles/{model}/info.json'))
     meta=decode(z.read(f'vehicles/{model}/info_{config}.json')) if f'vehicles/{model}/info_{config}.json'in names else {}
    except (ValueError,KeyError) as e:errors.append({'model':model,'config':config,'error':str(e)});continue
    row={'model':model,'config':config,'type':info.get('Type'),'name':meta.get('Configuration',config),'rated':(model,config.lower())in rated,'archive':str(path)}
    pc=decode(z.read(name)) if config.startswith('guineapig') else {}
    # Shipped crash-test configurations inside car models explicitly remove
    # the engine. They are test rigs, not self-propelled factory vehicles.
    unpowered_test=config.startswith('guineapig') and any(
     'engine' in slot.lower() and value=='' for slot,value in pc.get('parts',{}).items())
    if unpowered_test:
     row['reason']='Unpowered factory crash-test rig (engine explicitly removed)'
    if model in EXCLUDED or info.get('Type')in ('Prop','Trailer') or unpowered_test:
     excluded.append(row)
    else:rows.append(row)
 return {'configs':rows,'excluded':excluded,'errors':errors,'summary':{'found':len(rows),'rated':sum(r['rated']for r in rows),'missing':sum(not r['rated']for r in rows),'excluded':len(excluded),'missingByModel':dict(Counter(r['model']for r in rows if not r['rated'])),'types':dict(Counter(r['type']for r in rows))}}
def main():
 p=argparse.ArgumentParser();p.add_argument('--vehicles',type=Path,default=VEHICLES);p.add_argument('--seed',type=Path,default=Path('client/lua/ge/extensions/raceprep/ratings-seed.json'));p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 data=inventory(a.vehicles,json.loads(a.seed.read_text()));a.out.write_text(json.dumps(data,indent=2)+'\n');print(json.dumps(data['summary'],indent=2));print('errors',len(data['errors']))
if __name__=='__main__':main()
