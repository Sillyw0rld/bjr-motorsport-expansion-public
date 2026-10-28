-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Cross-plugin host metadata is not a client authority path.
local now=100;os.time=function() return now end
local wires={};local count=0
Util={JsonEncode=function(p) count=count+1;local s='wire'..count;wires[s]=p;return s end,JsonDecode=function(s) return wires[s] end,JsonPrettify=function(s) return s end}
local sent={}
MP={GetPlayers=function() return {[1]='One',[2]='Two',[3]='Three'} end,GetPlayerName=function(id) return tostring(id) end,
 RegisterEvent=function() end,CreateEventTimer=function() end,TriggerGlobalEvent=function() end,
 TriggerClientEvent=function(pid,event,wire) sent[#sent+1]={pid=pid,event=event,data=wires[wire],raw=wire} end}
local h=dofile('server/RacePrep/BJRHost.lua')
h.enabled=true;h.setLevel('test')
local a={runID='a',raceID=1,level='test',phase='race',remaining=2000,participants={1,2},racerKeyByPlayer={['1']='rk1',['2']='rk2'},laps={['1']=1,['2']=1}}
local b={runID='b',raceID=1,level='test',phase='race',remaining=3000,participants={3},racerKeyByPlayer={['3']='rk3'},laps={['3']=1}}
-- BJR state from its API (2.14.2): players.online staff, races.sessions runs
h.setPlayers({{id=1,staff=true},{id=2,staff=false},{id=3}});h.setRuns({a=a,b=b})
assert(h.canEdit(1) and not h.canEdit(2) and h.runFor(3)=='b')
assert(not h.cut(1,{raceID=2,lap=1}));assert(h.cut(1,{raceID=1,lap=1},{trackLimits='penalty',cutPenaltyAfter=0,cutPenaltySeconds=3}).racerKey=='rk1');assert(not h.cut(1,{raceID=1,lap=9}))
local rules={startLights=true,startType='standing',falseStartPenaltySeconds=5,trackLimits='penalty',cutPenaltyAfter=0,cutPenaltySeconds=3}
local penalties={}
local c=dofile('server/RacePrep/RaceControl.lua').new{path='server/RacePrep',host=h,rules=function() return rules end,read=function() return nil end,
 penalize=function(run,key,ms) penalties[#penalties+1]={run,key,ms} end}
c.snapshot({level='test',phase='none',participants={}});c.snapshot(a);c.snapshot(b)
c.event(1,{runID='b',kind='falseStart'});c.event(1,{runID='a',kind='falseStart'})
local res={runID='a',raceID=1,rows={{playerID=1,racerKey='rk1',total=68000,position=1,bjrPenaltyMs=8000,lapList={{lap=1,time=60000,sectors={20000,20000,20000}}}}}}
h.results(res,rules);assert(res.rows[1].total==68000 and res.rows[1].best==nil and res.rows[1].penalty==8000)
c.applyPenalties(res);assert(res.rows[1].total==68000 and res.rows[1].falseStart and penalties[1][2]=='rk1','BJR total once; false start sent by racer key')
local other={runID='b',raceID=1,rows={{playerID=3,total=60000,position=1}}};c.applyPenalties(other);assert(other.rows[1].total==60000)
local authoritative={runID='a',raceID=1,rows={{playerID=2,racerKey='rk2',total=120000,position=1,laps=2},{playerID=1,racerKey='rk1',total=68000,position=2,laps=1}}}
c.applyPenalties(authoritative)
assert(authoritative.rows[1].playerID==2 and authoritative.rows[2].total==68000,'lapped finisher keeps BJR position even with a shorter total')
RacePrepGetControl(1);local latest=sent[#sent];assert(latest.pid==1 and latest.data.runID=='a','get control routes by session')
now=106;assert(not h.canEdit(1) and not h.runFor(1),'stale host metadata fails closed')
RacePrepTrackSet(1,'{}');assert(sent[#sent].raw:find("waiting for the BeamJoy-Revived plugin API",1,true),'stale BJR state is not misreported as missing admin permission')
print('PASS: native server authority, current-lap cuts, concurrent same-layout results and private control views')
local detail={runID='detail',rows={
 {playerID=1,racerKey='rk1',laps=2,lapList={
  {lap=1,time=61000,sectors={21000,20000,20000}},
  {lap=2,time=60000,sectors={20000,21000,19000}}
 }},
 {playerID=2,laps=1,lapList={{lap=1,time=62000,sectors={22000,20000,20000}}}}
}}
h.cuts.detail={['rk1']={['2']=1}}
h.results(detail,{trackLimits='invalid'})
assert(detail.rows[1].best.time==61000 and detail.rows[1].bestAny.time==60000 and detail.rows[1].bestAny.invalid)
assert(detail.rows[1].theoretical==61000 and detail.rows[1].fastestLap and detail.rows[2].lapsDown==1)
print('PASS: best invalid/valid separation, theoretical sectors, fastest-valid marker and laps down')

local incomplete={runID='partial',sectorCount=3,rows={{playerID=1,lapList={{lap=1,time=60000,sectors={20000}}}}}}
h.results(incomplete,{trackLimits='invalid'});assert(not incomplete.rows[1].theoretical,'never invent a theoretical lap from incomplete sectors')

-- F4: 10 s lobby idle (20 ticks of 500 ms, 4 lobby players + 6 freeroam players)
-- sends ~20 RacePrepControl events (every 2 s to the 4 lobby players), not ~200
do
 local players={}
 for i=0,9 do players[i]='P'..i end
 MP.GetPlayers=function() return players end
 now=200
 local grid={runID='g1',raceID=1,level='test',phase='grid',remaining=0,participants={0,1,2,3},laps={['0']=1,['1']=1,['2']=1,['3']=1}}
 h.setPlayers({{id=0,staff=true}});h.setRuns({g1=grid})
 local idle=dofile('server/RacePrep/RaceControl.lua').new{path='server/RacePrep',host=h,rules=function() return rules end,read=function() return nil end}
 -- initial sync tick (sends 1 to each of 6 freeroam + 1 to each of 4 grid players)
 idle.snapshot({level='test',phase='none',participants={}})
 idle.snapshot(grid)
 local controlEvents,encodeBefore=0,count
 MP.TriggerClientEvent=function(pid,event,wire)
  sent[#sent+1]={pid=pid,event=event,data=wires[wire],raw=wire}
  if event=='RacePrepControl' then controlEvents=controlEvents+(pid==-1 and 10 or 1) end
 end
 for step=1,20 do -- 10 s at 500 ms ticks
  now=200+math.floor(step/2)
  h.at=now
  idle.snapshot({level='test',phase='none',participants={}})
  for _,state in pairs(h.runs) do idle.snapshot(state) end
  RacePrepControlTick()
 end
 local encodes=count-encodeBefore
 assert(controlEvents==20,'expected 20 RacePrepControl events over 10 s idle lobby, got '..controlEvents)
 assert(encodes==5,'state encoded once per 2 s publish (5 times), got '..encodes)
 print('PASS: 10 s lobby idle sends 20 RacePrepControl events (5 encodes), no neutral/run signature thrash')
end

-- Drivers must survive the real BJR metadata -> control publication path.
-- JSON maps use text IDs, unlike MP.GetPlayers and numeric result-row IDs.
do
 h.names={['0']='Account driver',['1']='Guest driver'}
 local profiles={schema=1,seen={},drivers={
  account={name='Old name',races=5,wins=2,laps=22,contacts=0,kilometres=107.85,safety=2.675},
  guest={name='Guest driver',races=6,wins=1,laps=12,contacts=2,kilometres=50,safety=2.8}}}
 local identities={[0]='account',[1]='guest'}
 local stats=dofile('server/RacePrep/RaceControl.lua').new{
  path='server/RacePrep',host=h,rules=function() return rules end,
  read=function(path) if path:match('/drivers%.json$') then return profiles end end,
  identity=function(pid) return identities[pid] end}
 stats.snapshot({level='test',phase='none',participants={}})
 RacePrepGetControl(0)
 local view
 for i=#sent,1,-1 do if sent[i].event=='RacePrepControl' then view=sent[i].data.driverStats;break end end
 local byID={};for _,row in ipairs(view or {}) do byID[row.playerID]=row end
 assert(byID[0] and byID[0].races==5 and byID[0].laps==22 and byID[0].safety==2.675 and not byID[0].provisional,
  'free-roam Drivers payload shows saved account data, not an empty profile')
 assert(byID[1] and byID[1].contacts==2 and byID[1].kilometres==50,'saved guest profile is also visible')
 assert(profiles.drivers.account.name=='Old name','view never rewrites stored profiles')
 print('PASS: BJR JSON name map publishes saved driver statistics and safety without data writes')
end
