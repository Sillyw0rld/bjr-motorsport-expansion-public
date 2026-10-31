#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Rebuild canonical low-end seed; preserve every individual old PI >300.

Preparation writes a private seed with measured raw baselines. Generate native
estimates against that seed, then finalize with --estimates. No server writes.
"""
import argparse,copy,json,subprocess,sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from run_vanilla_batch import lua
FIELDS=('pi','pi_speed','pi_technical')
def key(row):return row['model'],row['config'].lower()
def main():
 p=argparse.ArgumentParser();p.add_argument('--seed',type=Path,required=True);p.add_argument('--formula',type=Path,required=True);p.add_argument('--measurements',type=Path,required=True);p.add_argument('--inventory',type=Path,required=True);p.add_argument('--fit',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--estimates',type=Path);a=p.parse_args()
 seed=json.loads(a.seed.read_text());old=copy.deepcopy(seed['entries']);low=json.loads(a.fit.read_text())['lowRaw'];seed['constants']['curve']['lowRaw']=low;seed['constants']['rawRevision']=1
 fm={key(x):(k,x)for k,x in json.loads(a.formula.read_text())['entries'].items()}
 wanted={key(x)for x in json.loads(a.inventory.read_text())['configs']}
 measured={};flags=seed.setdefault('flags',{})
 for row in json.loads(a.measurements.read_text()):
  if row['raw']:measured[key(row)]=row
  elif row['origin']=='new':flags[row['model']+'/'+row['config']]='Rig rejected: '+row['reason']+'; rated by the formula'
 counts={'measuredRawRestored':0,'newMeasured':0,'measuredMissing':[]}
 for k,e in list(seed['entries'].items()):
  if e.get('native')and e['source']=='measured':
   row=measured.get(key(e));pair=fm.get(key(e))
   if row and pair:
    e['raw']=copy.deepcopy(row['raw']);e['formula']=copy.deepcopy(pair[1]['raw']);counts['measuredRawRestored']+=1
   else:counts['measuredMissing'].append(k)
 for identity,row in measured.items():
  if row['origin']!='new' or identity not in wanted or identity not in fm:continue
  k,formula=fm[identity]
  if k in old and old[k]['source']=='measured':continue
  seed['entries'][k]={'model':formula['model'],'config':formula['config'],'parts':formula['parts'],'native':True,'measured':True,'source':'measured','raw':copy.deepcopy(row['raw']),'formula':copy.deepcopy(formula['raw'])}
  seed.setdefault('baselines',{})[formula['model']+'/'+formula['config']]=k;counts['newMeasured']+=1
 if a.estimates:
  for k,e in json.loads(a.estimates.read_text())['entries'].items():
   if key(e)not in wanted:continue
   if k not in seed['entries']or seed['entries'][k]['source']=='computed':seed['entries'][k]=e
 # Use the production Lua curve, including its frozen upper branch.
 values=sorted({e.get('raw',{}).get(f,e.get(f,100))for e in seed['entries'].values()for f in FIELDS})
 with tempfile.TemporaryDirectory()as td:
  data=Path(td)/'input.lua';data.write_text('return '+lua({'constants':seed['constants'],'values':values}))
  code="package.path='client/lua/?.lua;'..package.path;local R=require('ge/extensions/raceprep/rating');local d=dofile(arg[1]);for _,v in ipairs(d.values)do io.write(R.curve(v,d.constants),'\\n')end"
  script=Path(td)/'curve.lua';script.write_text(code)
  result=subprocess.run(['luajit',str(script),str(data)],check=True,text=True,capture_output=True)
 mapped=dict(zip(values,map(int,result.stdout.splitlines())))
 protected=0
 for k,e in seed['entries'].items():
  before=old.get(k,{})
  for f in FIELDS:
   if before.get(f,0)>300:
    e[f]=before[f];e.setdefault('raw',{})[f]=before.get('raw',{}).get(f,before[f]);protected+=1
   else:e[f]=mapped[e.get('raw',{}).get(f,e.get(f,100))]
  e['class']=next((label for limit,label in [(999,'X'),(901,'P'),(801,'R'),(701,'S'),(601,'A'),(501,'B'),(401,'C'),(301,'D')]if e['pi']>=limit),'E')
  if e.get('native'):
   seed.setdefault('baselines',{})[e['model']+'/'+e['config']]=k
   if e['source']=='computed':e['ratingRevision']=1;e.pop('parts',None)
 counts['protectedIndividualValues']=protected
 a.out.write_text(json.dumps(seed,indent=1)+'\n');print(json.dumps(counts,indent=2))
if __name__=='__main__':main()
