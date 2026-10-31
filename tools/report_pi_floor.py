#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Evaluate a frozen low-end fit; never choose parameters from blind results."""
import argparse,csv,json,statistics,subprocess,tempfile
from collections import Counter
from pathlib import Path
from run_vanilla_batch import lua

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('before','formula','measurements','fit','out'):p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();before=json.loads(a.before.read_text());after=json.loads(Path('client/lua/ge/extensions/raceprep/ratings-seed.json').read_text());fit=json.loads(a.fit.read_text());formula=json.loads(a.formula.read_text())
 fm={(r['model'],r['config'].lower()):r for r in formula['entries'].values()}
 old={(r['model'],r['config'].lower()):r for r in before['entries'].values()};new={(r['model'],r['config'].lower()):r for r in after['entries'].values()}
 measurements=json.loads(a.measurements.read_text());raws={r['raw']['pi']for r in measurements if r['raw']}|{r['raw']['pi']for r in fm.values()}
 with tempfile.TemporaryDirectory()as td:
  path=Path(td)/'curve.lua';path.write_text("package.path='client/lua/?.lua;'..package.path;local R=require('ge/extensions/raceprep/rating');local d="+lua({'values':sorted(raws),'constants':after['constants']})+";for _,v in ipairs(d.values)do io.write(R.curve(v,d.constants),'\\n')end")
  result=subprocess.run(['luajit',str(path)],capture_output=True,text=True,check=True)
 converted=dict(zip(sorted(raws),map(int,result.stdout.splitlines())))
 samples=[];blind=[]
 for r in measurements:
  if r['origin']!='new':continue
  key=(r['model'],r['config'].lower());f=fm.get(key);n=new.get(key);o=old.get(key)
  row={'model':key[0],'config':r['config'],'formulaRaw':f['raw']['pi']if f else None,'measuredRaw':r['raw']['pi']if r['raw']else None,'oldPI':o['pi']if o else None,'newPI':n['pi']if n else None,'formulaPI':converted[f['raw']['pi']]if f else None,'measuredPI':converted[r['raw']['pi']]if r['raw']else None,'source':n['source']if n else None,'rejection':r['reason']}
  samples.append(row)
  if key[0]in fit['heldOutModels']and row['measuredPI']is not None:
   blind.append(row|{'error':row['formulaPI']-row['measuredPI']})
 protected=[(k,f,v,after['entries'].get(k,{}).get(f))for k,e in before['entries'].items()for f in ('pi','pi_speed','pi_technical')if (v:=e[f])>300]
 changes=[x for x in protected if x[2]!=x[3]]
 def hist(seed):
  rows=[r for r in seed['entries'].values()if r.get('native')];pi=[r['pi']for r in rows]
  return {'rated':len(rows),'at100':pi.count(100),'bins':{str(lo)+'–'+str(hi):sum(lo<=v<=hi for v in pi)for lo,hi in [(100,100),(101,149),(150,199),(200,249),(250,300)]}}
 result={'lowRaw':fit['lowRaw'],'blindMAE':statistics.mean(abs(r['error'])for r in blind),'blindWorst':max(abs(r['error'])for r in blind),'blind':blind,'protectedIndividualValues':len(protected),'protectedChanges':changes,'before':hist(before),'after':hist(after),'newAttempts':len(samples),'newAccepted':sum(r['measuredPI']is not None for r in samples),'samples':samples,'formulaComputed':len(fm),'formulaErrors':formula['errors'],'nativeSources':dict(Counter(r['source']for r in after['entries'].values()if r.get('native')))}
 a.out.mkdir(parents=True,exist_ok=True);(a.out/'results.json').write_text(json.dumps(result,indent=2)+'\n')
 with (a.out/'sample.csv').open('w')as stream:
  w=csv.DictWriter(stream,fieldnames=list(samples[0]),lineterminator='\n');w.writeheader();w.writerows(samples)
 print(json.dumps({k:v for k,v in result.items()if k not in ('samples','blind')},indent=2))
if __name__=='__main__':main()
