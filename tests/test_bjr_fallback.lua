-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- 2.32.0: BJR without phases (released 2.0.1) falls back to classic weekends,
-- BJR:ME-applied penalties and Ready-time checks; BJR with phases keeps the
-- single-event weekend. The API lists are read from the real BJR sources
-- (tests/fixtures/bjr-api-info.json).
local function read(p) local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local info=assert(loadstring(io.popen('python3 -I tests/json2lua.py tests/fixtures/bjr-api-info.json'):read('*a')))()
local Api=dofile('server/RacePrep/BJRApi.lua')

-- capabilities from the real server.info lists
local released,dev=Api.capabilities(info.released_2_0_1),Api.capabilities(info.development_2488)
assert(not released.phases and not released.penalties and not released.join and not released.awards,'released 2.0.1 lacks phases, race.penalize, raceJoin and award events')
assert(dev.phases and dev.penalties and dev.join and dev.awards,'development 2488 has every feature')
-- hooks.register alone must not count as raceJoin support
assert(not Api.capabilities({methods=info.released_2_0_1.methods,events=info.released_2_0_1.events}).phases)

-- the yellow startup block: how to switch to development and back
local lines=table.concat(Api.fallbackLines(released,Api.TESTED_DEV),'\n')
assert(lines:find('CLASSIC mode',1,true) and lines:find('bj update channel development',1,true) and lines:find('"bj update"',1,true))
assert(lines:find('bj update channel release',1,true) and lines:find('BeamJoyData/update/backup-',1,true),'the way back is explained')
assert(lines:find('race.penalize',1,true) and lines:find('at Ready',1,true) and lines:find('Most places gained',1,true))
assert(#Api.fallbackLines(dev,Api.TESTED_DEV)==0,'nothing printed with every feature present')

-- grid order answers: released BJR reads player IDs, development BJR racer keys
local order={{racerKey='7'},{racerKey='3'},{racerKey='9'}} -- gridOrderFor's shape (player ID as the key)
local a=Api.gridAnswer(order,{{id=3,name='B'},{id=7,name='A'}})
assert(a.by==nil and a.order[1]==7 and a.order[2]==3 and #a.order==2,'released: numeric player IDs, absent racers dropped')
local d=Api.gridAnswer({{racerKey='rk2'},{racerKey='rk1'}},{{id=1,racerKey='rk1'},{id=2,racerKey='rk2'}})
assert(d.by=='racerKey' and d.order[1]=='rk2','development: racer keys as before')
assert(next(Api.gridAnswer({},{{id=1}}))==nil)

-- penalties added by BJR:ME when BJR cannot take them (as 2.16 did)
local now=100;os.time=function() return now end
local wires={};local count=0
Util={JsonEncode=function(p) count=count+1;local s='wire'..count;wires[s]=p;return s end,JsonDecode=function(s) return wires[s] end,JsonPrettify=function(s) return s end}
MP={GetPlayers=function() return {[1]='One',[2]='Two'} end,GetPlayerName=function(id) return tostring(id) end,
 RegisterEvent=function() end,CreateEventTimer=function() end,TriggerGlobalEvent=function() end,TriggerClientEvent=function() end}
local h=dofile('server/RacePrep/BJRHost.lua')
h.enabled=true;h.setLevel('test')
local run={runID='r',raceID=1,level='test',phase='race',remaining=2000,participants={1,2},racerKeyByPlayer={['1']='1',['2']='2'},laps={['1']=1,['2']=1}}
h.setPlayers({{id=1},{id=2}});h.setRuns({r=run})
local rules={startLights=true,startType='standing',falseStartPenaltySeconds=5,trackLimits='penalty',cutPenaltyAfter=0,cutPenaltySeconds=3}
assert(h.cut(1,{raceID=1,lap=1},rules).penaltyMs==3000)
local sent={}
local c=dofile('server/RacePrep/RaceControl.lua').new{path='server/RacePrep',host=h,rules=function() return rules end,read=function() return nil end,
 localPenalties=function() return true end,penalize=function(...) sent[#sent+1]={...} end}
c.snapshot(run);c.event(1,{runID='r',kind='falseStart'})
assert(#sent==0,'no race.penalize call on a BJR without it')
-- BJR's totals carry no penalties: driver 1 crossed first by 2 s
local res={runID='r',raceID=1,rows={
 {playerID=1,racerKey='1',total=60000,position=1,laps=1,lapList={{lap=1,time=60000,sectors={}}}},
 {playerID=2,racerKey='2',total=62000,position=2,laps=1,lapList={{lap=1,time=62000,sectors={}}}}}}
h.results(res,rules,true);assert(res.rows[1].penalty==3000 and res.rows[1].total==63000,'track-limit penalty added to the total')
c.applyPenalties(res)
assert(res.rows[1].playerID==2 and res.rows[2].playerID==1 and res.rows[2].total==68000 and res.rows[2].falseStart,'3 s cut + 5 s false start drop driver 1 behind driver 2')
assert(res.rows[1].position==1 and res.rows[2].gap==6000)
-- a lapped car stays behind even with a shorter penalised total
local lapped={runID='r',raceID=1,rows={{playerID=2,racerKey='2',total=120000,laps=2,position=1},{playerID=1,racerKey='1',total=50000,laps=1,position=2}}}
c.applyPenalties(lapped);assert(lapped.rows[1].playerID==2,'more laps first')
-- with race.penalize (development BJR) nothing is added twice
local h2=dofile('server/RacePrep/BJRHost.lua');h2.enabled=true
local res2={runID='x',raceID=1,rows={{playerID=1,racerKey='1',total=63000,bjrPenaltyMs=3000,laps=1,lapList={{lap=1,time=60000,sectors={}}}}}}
h2.cuts.x={['1']={['1']=1}};h2.results(res2,rules,false);assert(res2.rows[1].total==63000 and res2.rows[1].penalty==3000,'BJR total used once')

-- RacePrep: the weekend picks its mode from BJR's capabilities
local main=read('server/RacePrep/RacePrep.lua')
assert(main:find("weekend.mode = phased and 'phases' or 'classic'",1,true),'mode chosen per weekend')
assert(main:find("local phased=bjrCan('phases')",1,true) and main:find("if weekend.mode=='phases' and bjrApi",1,true),'phase calls only in phase mode')
assert(main:find("local q = not bjrCan('phases') and lastQuali",1,true),'classic qualifying feeds the BJR grid hook')
assert(main:find("open the race lobby for",1,true),'classic grid tells players to open the lobby')
assert(select(2,main:gsub("weekend.mode=='classic' and",''))>=3,'early lobbies/countdowns/finishes during classic practice are ignored')
assert(main:find('warn=logWarn',1,true),'fallback block printed in yellow')
local ui=read('client/ui/modModules/raceprepBJR/raceprep.html');assert(ui:find("weekend.mode==='classic'",1,true) and ui:find("BeamJoy's race menu",1,true))
print('PASS: real BJR 2.0.1 vs dev 2488 capabilities, yellow fallback block with dev/back commands, player-ID grid answers, BJR:ME-applied penalties with lap-aware order, classic weekend mode')
