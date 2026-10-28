-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Failed profile publication must not consume a result or change visible stats.
local Persist=dofile('server/RacePrep/Persistence.lua')
local now=100
os.time=function() return now end
local wires,n={},0
Util={JsonEncode=function(t) n=n+1;local k='wire'..n;wires[k]=Persist.copy(t);return k end,
 JsonDecode=function(k) return Persist.copy(wires[k]) end,JsonPrettify=function(k) return k end}
local sent={}
MP={GetPlayers=function() return {[1]='Driver'} end,GetPlayerName=function() return 'Driver' end,
 RegisterEvent=function() end,CreateEventTimer=function() end,TriggerGlobalEvent=function() end,
 TriggerClientEvent=function(_,event,data) if event=='RacePrepControl' then sent[#sent+1]=wires[data] end end}
local disk={}
local fail=true
local path='server/RacePrep'
local host=dofile(path..'/BJRHost.lua');host.enabled=true;host.setLevel('test');host.setPlayers({{id=1,staff=true}})
local identity='account:old'
local function make()
 return dofile(path..'/RaceControl.lua').new{path=path,host=host,rules=function() return {safetyRating=true} end,
  identity=function() return identity end,resultIdentity=function() return identity end,
  read=function(p) return Persist.copy(disk[p]) end,
  persistence={copy=Persist.copy,write=function(p,v)
   if fail and p==path..'/drivers.json' then return false end
   disk[p]=Persist.copy(v);return true
  end}}
end
local c=make()
local res={key='run',runID='run',raceID=1,level='test',rows={{playerID=1,racerKey='racer1',name='Driver',position=1,status='FIN',laps=1,lapList={{time=60000}},best={time=60000}}}}
c.recordResult(res)
assert(not disk[path..'/drivers.json'],'failed profile write does not become durable')
assert(disk[path..'/records-pending.json'].run.identities.racer1=='account:old','durable retry captures original identity')
-- Simulate a server restart and a reused player ID before storage recovers.
identity='account:new';c=make();fail=false;now=106;RacePrepControlTick()
local profiles=disk[path..'/drivers.json']
assert(profiles.drivers['account:old'].races==1 and not profiles.drivers['account:new'],'replay attributes the old racer, never the current PID owner')
assert(not next(disk[path..'/records-pending.json']),'queue clears only after persistence')
now=112;RacePrepControlTick()
assert(disk[path..'/drivers.json'].drivers['account:old'].races==1,'replay is idempotent')
-- Checked writes retain the previous file when the temporary file cannot write.
local tmp=os.tmpname();local f=assert(io.open(tmp,'w'));f:write('old');f:close()
local open=io.open
io.open=function(p,mode)
 if p==tmp..'.tmp' and mode=='w' then return {write=function() return nil,'disk full' end,close=function() return true end} end
 return open(p,mode)
end
assert(not Persist.write(tmp,{value=1}));io.open=open
f=assert(io.open(tmp));assert(f:read('*a')=='old');f:close();os.remove(tmp)
print('PASS: failed profile writes, durable retry, restart/reconnect identity, dedup and retained previous file')
