-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local U=dofile('server/RacePrep/ReleaseUpdates.lua')
local t, commands, logs, files=100, {}, {}, {}
local o={path='Resources/Server/RacePrep',windows=false}
o.now=function() return t end
o.exists=function() return true end
o.read=function(p) return files[p] end
o.write=function(p,v) files[p]=v;return true end
o.execute=function(c) commands[#commands+1]=c end
o.log=function(m) logs[#logs+1]=m end
local u=U.new(o)
u.tick();assert(#commands==0 and logs[1]:find('inactive'),'placeholder never makes a network request')
assert(u.command('unrelated')==nil)
u.command('bjrme help');assert(logs[#logs]:find('bjrme check%-update'))
u.command('bjrme update');assert(#commands==1 and commands[1]:find('%-%-update%-stage') and commands[1]:find('&$'))
u.command('raceprep update');assert(#commands==1,'busy requests not duplicated (old raceprep form still works)')
files['.raceprep-update/request-'..u.pending.id..'.json']={status='available',message='stale',requestId='old'}
u.tick();assert(u.pending,'ignore a previous result even in the same second')
files['.raceprep-update/request-'..u.pending.id..'.json']={status='staged',message='restart through launcher',requestId=u.pending.id}
files['.raceprep-update/status.json']=files['.raceprep-update/request-'..u.pending.id..'.json']
u.tick();assert(not u.pending and logs[#logs]:find('restart'))
u.command('bjrme update-status');assert(logs[#logs]:find('restart'))
files[o.path..'/updates.json']={enabled=true,repository='author/project',checkEveryHours=24}
t=t+86401;u.tick();assert(#commands==2 and commands[2]:find('%-%-update%-check'))
t=t+601;u.tick();assert(not u.pending and logs[#logs]:find('timed out'))
o.windows=true;u=U.new(o);u.command('bjrme check-update');assert(commands[#commands]:find('^start "" /B') and commands[#commands]:find('generator.exe'))
-- optional mods (2026-10-21): reminders from the launcher's status file, ignore, get
o.windows=false;u=U.new(o);u.nextCheck=t+1e9;commands={}
local status=o.path..'/optional-mods-status.json'
local function line(k) return 'Optional: '..k..' not installed. Type "bjrme get '..k..'" to download it, or "bjrme optional ignore '..k..'" to stop this reminder.' end
files[status]={mods={{key='kts',name='KTS',state='missing'},{key='ddp',name='DDP',state='outdated',installed='1.2',latest='2.0'},{key='fluidspill',name='FS',state='current'}},reminders={line('kts'),line('ddp')}}
assert(#u.reminders()==2)
local view=u.optionalView();assert(#view==2 and view[1].key=='kts' and view[2].installed=='1.2','staff see only mods needing attention')
u.command('bjrme optional ignore ddp')
assert(files[o.path..'/optional-mods.json'].ignore[1]=='ddp' and #u.reminders()==1 and u.reminders()[1]:find('get kts"',1,true),'ignored at once, before the next check')
assert(#u.optionalView()==1,'ignored mods leave the staff list')
u.command('bjrme optional unignore ddp');assert(#files[o.path..'/optional-mods.json'].ignore==0)
u.command('bjrme optional ignore nope');assert(logs[#logs]:find('unknown optional mod'))
u.command('bjrme get nope');assert(logs[#logs]:find('unknown optional mod') and #commands==0)
u.command('bjrme get ddp');assert(#commands==1 and commands[1]:find('%-%-optional%-get ddp %-%-optional%-request%-id') and commands[1]:find('%.bjrme%-optional%.log'))
files['.bjrme-optional/request-'..u.pending.id..'.json']={status='staged',message='DDP 2.0 verified and staged',requestId=u.pending.id}
u.tick();assert(not u.pending and logs[#logs]:find('verified and staged'))
u.command('bjrme optional');assert(commands[#commands]:find('%-%-optional%-check'))
print('PASS: console-only release commands, disabled placeholder, periodic background checks, stale-result and overlap guards; optional mods reminders, ignore and get')
