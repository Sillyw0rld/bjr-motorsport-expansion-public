#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Select the least-compressed low-end span meeting the requested training MAE.

The specified independent validation sample is held out by whole model, including any old
reference runs of those families. Formula coefficients and upper curve stay
frozen. Report blind MAE even when the target is missed; never fit to it.
"""
import argparse,json,math,statistics
from pathlib import Path

def curve(raw,low):
 if raw>300:raise ValueError('This fitter evaluates the low end only')
 return max(100,math.floor(100+200*(raw-low)/(300-low)+.5))
def main():
 p=argparse.ArgumentParser();p.add_argument('--formula',type=Path,required=True);p.add_argument('--measurements',type=Path,required=True);p.add_argument('--jobs',type=Path,nargs='+',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--training-target',type=float,default=10);a=p.parse_args()
 fm={(x['model'],x['config'].lower()):x['raw']['pi']for x in json.loads(a.formula.read_text())['entries'].values()}
 families=set()
 for f in a.jobs:
  rows=json.loads(f.read_text());rows=rows if isinstance(rows,list)else[rows];families.update(x['model']for x in rows)
 train=[];blind=[]
 latest={}
 for row in json.loads(a.measurements.read_text()):latest[(row['model'],row['config'].lower())]=row
 for row in latest.values():
  raw=row.get('raw');pred=fm.get((row['model'],row['config'].lower()))
  if raw and pred is not None and max(raw['pi'],pred)<=300:
   x={'model':row['model'],'config':row['config'],'formulaRaw':pred,'measuredRaw':raw['pi']}
   if row['model']not in families:train.append(x)
   elif row['origin']=='new':blind.append(x)
 if not train:raise SystemExit('No independent training families')
 candidates=[]
 for low in range(-300,-2501,-50):
  mae=statistics.mean(abs(curve(x['formulaRaw'],low)-curve(x['measuredRaw'],low))for x in train)
  candidates.append({'lowRaw':low,'trainMAE':mae})
 chosen=next((x for x in candidates if x['trainMAE']<=a.training_target),None)
 if chosen is None:raise SystemExit('No low-end fit meets training target')
 low=chosen['lowRaw']
 for x in train+blind:
  x.update(formulaPI=curve(x['formulaRaw'],low),measuredPI=curve(x['measuredRaw'],low));x['error']=x['formulaPI']-x['measuredPI']
 result={'method':'Piecewise linear low end, floored only on display. Training excludes every validation model. Existing v7 formula and upper curve frozen.',**chosen,'trainingTarget':a.training_target,'heldOutModels':sorted(families),'training':train,'blind':blind,'blindMAE':statistics.mean(abs(x['error'])for x in blind)if blind else None,'blindWorst':max((abs(x['error'])for x in blind),default=None),'candidates':candidates}
 a.out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items()if k not in ['candidates','training','blind','method']},indent=2));print('training',len(train),'blind',len(blind))
if __name__=='__main__':main()
