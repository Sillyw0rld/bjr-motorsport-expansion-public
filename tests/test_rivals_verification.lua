-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local F=dofile('tests/rivals_fixture.lua')
local samples=F.samples()
local function drive(e,transform)
 for i,s in ipairs(samples) do
  local c={at=s.at,raw={}};for k,v in pairs(s.raw) do c.raw[k]=v end
  if transform then transform(c,i,e) end
  e.feed(c)
 end
end
local e=F.new();drive(e);e.post(1)
assert(#e.saved==1 and e.saved[1].rows[1].best.time==12000,'official server crossing time')
assert(e.saved[1].verified and e.saved[1].rows[1].verified and e.saved[1].rows[1].best.verified)
assert(e.saved[1].verification.gameTime==12000 and #e.saved[1].rows[1].best.trace>5)
assert(not e.saved[1].rows[1].best.trace[1].fake,'claimed trace cannot become proof/reference')
local oldToken=e.token;e.ms=e.ms+250;e.post(1,12000,{lapToken=oldToken})
assert(#e.saved==1 and e.messages[1].message:find('Replayed'),'one-time consumed lap token')
e=F.new();drive(e);e.post(1,8000);assert(#e.saved==0 and e.messages[1].message:find('shorter'),'slow motion refused')
e=F.new();e.post(1,6000);assert(#e.saved==0 and e.messages[1].message:find('No server'),'forged valid and trace cannot count')
e=F.new();drive(e,function(c) c.at=c.at+(c.at%150==0 and 20 or 0) end);e.post(1,11900)
assert(#e.saved==1 and e.saved[1].rows[1].best.time~=11900,'jitter accepted but game time never official')
e=F.new();drive(e,function(c) c.raw.pos={c.raw.pos[1],math.max(0,11-math.abs(c.raw.pos[1]-60)),0} end);e.post(1)
assert(#e.saved==0 and e.messages[1].message:lower():find('missed gate 2'),'missed intermediate gate')
e=F.new();drive(e,function(c,i) if i==80 then c.raw.pos={500,0,0} end end);e.post(1)
assert(#e.saved==0,'teleport voids lap')
e=F.new();drive(e,function(c,i,env) if i==80 then env.manager.vehicleEvent(1,0,'Reset') end end);e.post(1)
assert(#e.saved==0,'native reset voids lap')
e=F.new();drive(e,function(c,i,env) if i==80 then env.config='tune-b' end end);e.post(1)
assert(#e.saved==0 and e.messages[1].error:find('expired'),'server configuration change ends run')
e=F.new();drive(e,function(c,i,env) if i==80 then env.manager.vehicleEvent(1,0,'parts / tune edited') end end);e.post(1)
assert(#e.saved==0,'native edit ends run immediately')
e=F.new();local first=e.messages[1];e.ms=3000;assert(e.manager.start(1,{challenge='layout',practice=true,vehicle='1-0'}))
e.ms=3500;e.manager.lap(1,{id=first.id,lapToken=first.lapToken,time=12000,valid=true,cuts=0})
assert(#e.saved==0 and e.messages[1].error:find('expired'),'old session replay')
e=F.new();drive(e,function(c,i) if i>80 and i<100 then c.raw.tim=samples[80].raw.tim end end);e.post(1)
assert(#e.saved==0,'stale cached position cannot count')
e=F.new();drive(e,function(c,i) if i>80 then c.at=c.at+500 end end);e.post(1)
assert(#e.saved==0,'sampling interruption cannot count')
-- Early client finish is queued until the server observes the finish.
e=F.new();for i,s in ipairs(samples) do if i==242 then e.post(1) end;e.feed(s) end
assert(#e.saved==1,'small client/server delivery order difference accepted')
-- Ordinary/old Rivals files are preserved, but cannot rank or suppress a
-- slower new verified PB. Empty boards remain selectable for first runs.
local legacy={kind='rivals',runID='old',raceID=1,recordContext={layout='l',rulesKey='r'},rows={{model='car',class='B',pi=550,rivalDriver='d',buildKey='b',best={time=10}}}}
local groups={};F.Records.add(groups,legacy)
local view=F.Records.view(groups);assert(#view==1 and #view[1].rows==0)
assert(groups['l:r:B'].bests['d:car'].verified==false and legacy.verified==nil,'old data derives unverified without deletion')
local good=e.saved[1];good.recordContext={layout='l',rulesKey='r'};good.rows[1].rivalDriver='d';F.Records.add(groups,good)
view=F.Records.view(groups);assert(#view[1].rows==1 and view[1].rows[1].verified)
-- Foreign vehicle reset must not affect the selected run.
e=F.new();drive(e,function(c,i,env) if i==80 then env.manager.vehicleEvent(1,1,'Reset') end end);e.post(1);assert(#e.saved==1)
-- A fake valid flag with no client cuts is insufficient when proof is invalid.
e=F.new();drive(e);e.post(1,12000,{cuts=1});assert(#e.saved==0)
e=F.new();e.api.save=function() return false end;drive(e);e.post(1)
assert(#e.saved==0 and e.messages[1].lap.verified==false and e.messages[1].message:find('could not be saved'),'failed publication is not reported as a record')
-- Real loop: start east, follow every gate, return away from the line.
local loop={loopable=true,gates={{pos={x=0,y=0,z=0},dir={x=1,y=0,z=0},width=10},{pos={x=60,y=0,z=0},dir={x=1,y=0,z=0},width=10}}}
local verifier=assert(F.Verification.new(loop,100));local t=0;local result
local points={{-1,0},{61,0},{61,20},{-1,20},{-1,0},{1,0}}
for i=2,#points do
 local a,b=points[i-1],points[i];local n=math.ceil(math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)/.5)
 for j=0,n do t=t+50;local p={a[1]+(b[1]-a[1])*j/n,a[2]+(b[2]-a[2])*j/n,0};result=verifier.sample(t,{pos=p,tim=t},'') or result end
end
assert(result and result.time>10000,'loop finish returns to start after every gate')
print('PASS: server crossing timing, slow motion, forged validity, jitter, gates, teleport, reset/edit/config, replay, cache freshness, legacy policy and loop')
