#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Offline replay of the actual Lua backfill; input data is never modified."""
import argparse,json,math,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def lua(v):
    if v is None:return 'nil'
    if v is True:return 'true'
    if v is False:return 'false'
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,(int,float)):
        if not math.isfinite(v):raise ValueError('Non-finite input')
        return repr(v)
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,dict):return '{'+','.join('['+lua(str(k))+']='+lua(x) for k,x in sorted(v.items()) if x is not None)+'}'
    raise TypeError(type(v))
def run(source,output):
    source,output=Path(source).resolve(),Path(output).resolve()
    # any server's live RacePrep folder, not only one machine's path
    if 'Resources/Server/RacePrep' in output.as_posix():raise ValueError('Offline backfill must not write live server data')
    output.mkdir(parents=True,exist_ok=True)
    def read(p,default):return json.loads(p.read_text()) if p.exists() else default
    data={'profiles':read(source/'drivers.json',{'drivers':{}}),'skills':read(source/'skills.json',{'players':{},'salt':'offline'}),
          'results':[json.loads(p.read_text()) for p in sorted((source/'history').glob('*.json'))[-1000:]],
          'moderation':read(source/'rivals-moderation.json',{'blocked':{},'removed':{}}),'challenges':read(source/'challenges.json',{}).get('picks',{}),'weeklies':read(source/'weekly-rivals.json',{}).get('picks',{}),'state':read(output/'progression.json',{'schema':1,'drivers':{},'seen':{}})}
    if not isinstance(data['moderation'],dict) or not isinstance(data['moderation'].get('blocked'),dict) or not isinstance(data['moderation'].get('removed'),dict):raise ValueError('Corrupt Rivals moderation data')
    with tempfile.TemporaryDirectory(prefix='bjr-backfill-') as tmp:
        fixture=Path(tmp)/'input.lua';fixture.write_text('return '+lua(data))
        result=subprocess.run(['luajit','tools/backfill_progression.lua',str(fixture)],cwd=ROOT,text=True,capture_output=True,check=True)
    state=json.loads(result.stdout);encoded=json.dumps(state,ensure_ascii=False,sort_keys=True,indent=2)+'\n'
    target=output/'progression.json';changed=not target.exists() or target.read_text()!=encoded
    if changed:
        temp=target.with_suffix('.tmp');temp.write_text(encoded);temp.replace(target)
    report={'changed':changed,**state.get('backfill',{}),'drivers':[]}
    for d in state['drivers'].values():report['drivers'].append({'name':d.get('name','Unknown'),'licence':d.get('licence','Rookie'),'level':int((math.sqrt(25+max(0,d.get('xp',0))*.04)-3)//2),'achievements':len(d.get('achievements',{}))})
    report['drivers'].sort(key=lambda d:d['name'])
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    print(json.dumps(run(a.input,a.output),ensure_ascii=False,indent=2))
