-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local function assertEq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
MP={RegisterEvent=function() end,CreateEventTimer=function() end,TriggerGlobalEvent=function() end,TriggerClientEvent=function() end}
Util={JsonEncode=function(p) return p end,JsonDecode=function(p) return p end}
local rules={startLights=true,startType='standing',falseStartPenaltySeconds=5}
local control=dofile('server/RacePrep/RaceControl.lua').new({rules=function() return rules end,path='server/RacePrep',read=function() return nil end})
control.snapshot({raceID=1,runID='100',phase='race',remaining=2500,participants={0,1}})
control.event(7,{runID='100',kind='falseStart'});assert(not control.state.falseStarts['7'])
control.event(0,{runID='old',kind='falseStart'});assert(not control.state.falseStarts['0'])
control.event(0,{runID='100',kind='falseStart'});control.event(0,{runID='100',kind='falseStart'})
assertEq(control.state.falseStarts['0'],5000)
local result={raceID=1,runID='100',rows={{playerID=0,position=1,total=60000,penalty=5000,falseStartPenalty=5000},
 {playerID=1,position=2,total=59000}}}
assert(control.validRun({runID='100',raceID=1}));assert(not control.validRun({runID='100',raceID=2}))
control.applyPenalties(result);assertEq(result.rows[1].playerID,1);assertEq(result.rows[2].total,60000)
assertEq(result.rows[2].penalty,5000)
local wrong={raceID=2,runID='100',rows={{playerID=0,total=50000,position=1}}}
control.applyPenalties(wrong);assertEq(wrong.rows[1].total,50000)
control.snapshot({phase='none',participants={}})
control.applyPenalties({raceID=1,runID='100',rows={{playerID=0,total=50000,position=1}}})
rules.startType='rolling';control.snapshot({runID='101',phase='race',remaining=3000,participants={0}})
control.event(0,{runID='101',kind='falseStart'});assert(not control.state.falseStarts['0'])

local realTime=os.time;local tick=100;os.time=function() return tick end
rules.yellowFlags=true;rules.startType='standing'
control.snapshot({raceID=1,runID='103',phase='race',elapsed=20,remaining=-20000,participants={0}})
local telemetry={runID='103',kind='telemetry',speed=0,onTrack=true,position={x=0,y=0,z=0}}
control.event(0,telemetry);tick=102;control.event(0,telemetry);assert(not next(control.state.hazards))
tick=103;control.event(0,telemetry);assert(control.state.hazards['0'])
telemetry.speed=10;control.event(0,telemetry);assert(not next(control.state.hazards))
telemetry.speed=0;tick=104;control.event(0,telemetry);tick=108;control.event(0,telemetry)
assert(not next(control.state.hazards),'stale stopped telemetry must rearm')
telemetry.speed=20;telemetry.position.x=10;control.event(0,telemetry)
telemetry.position.x=20;control.event(0,telemetry) -- same integer server second
assert((control.state.incidents['0'].distance or 0)>=20,'half-second telemetry distance must count')
telemetry.damage=100000;control.event(0,telemetry)
assert((control.state.incidents['0'].contacts or 0)==0,'raw damage alone is not an incident any more')
-- contact reports: the car that was hit loses nothing
control.snapshot({raceID=1,runID='104',phase='race',elapsed=20,remaining=-20000,participants={0,1,2}})
control.event(0,{runID='104',kind='contact',verdict='me',other=1})
control.event(1,{runID='104',kind='contact',verdict='other',other=0}) -- the hit car's copy of the same crash
local inc=control.state.incidents
assertEq(inc['0'].contacts,1);assert(not inc['1'] or (inc['1'].contacts or 0)==0,'victim keeps a clean record')
assertEq(inc['1'].hitBy,1)
tick=120;control.event(2,{runID='104',kind='contact',verdict='other',other=0})
assertEq(inc['0'].contacts,2);assertEq(inc['2'].contacts,0)
tick=130;control.event(1,{runID='104',kind='contact',verdict='shared',other=2})
assertEq(inc['1'].contacts,.5);assertEq(inc['2'].contacts,.5)
tick=140;control.event(2,{runID='104',kind='contact',verdict='self'})
assertEq(inc['2'].contacts,1.5)
tick=150;control.event(1,{runID='104',kind='contact',verdict='other',other=9})
assertEq(inc['1'].contacts,1.5) -- "hit by" a car not in the race: counts as own incident
-- yellow for a car stopped off the road (spin into the gravel)
control.snapshot({raceID=1,runID='105',phase='race',elapsed=20,remaining=-20000,participants={0}})
local off={runID='105',kind='telemetry',speed=0,onTrack=false,position={x=0,y=0,z=0}}
tick=200;control.event(0,off);tick=203;control.event(0,off);assert(control.state.hazards['0'],'stopped off track is a yellow')
os.time=realTime

-- broadcasts: only on change; in a race also every 2 s
local sentCount=0
MP.TriggerClientEvent=function() sentCount=sentCount+1 end
tick=1000;os.time=function() return tick end
control.snapshot({phase='none',participants={},level='mosport'})
local base=sentCount
for i=1,10 do control.snapshot({phase='none',participants={},level='mosport'}) end
assertEq(sentCount,base)
control.snapshot({raceID=1,runID='106',phase='grid',participants={0},level='mosport'});assertEq(sentCount,base+1)
control.snapshot({raceID=1,runID='106',phase='grid',participants={0},level='mosport'});assertEq(sentCount,base+1)
tick=1002;control.snapshot({raceID=1,runID='106',phase='grid',participants={0},level='mosport'});assertEq(sentCount,base+2)
RacePrepGetControl(5);assertEq(sentCount,base+3)
os.time=realTime
print('PASS: contact fault (victim clean), shared/self incidents, off-road yellow, change-only broadcasts')

-- track settings per map: rubber level stays, admin set/clean/full, wind
local tmp=os.tmpname();os.remove(tmp);os.execute('mkdir -p '..tmp..' && cp server/RacePrep/Championship.lua server/RacePrep/DriverStats.lua server/RacePrep/RubberMap.lua server/RacePrep/MarbleMap.lua '..tmp..'/')
Util.JsonPrettify=function(s) return s end
local files={}
Util.JsonEncode=function(p) return 'x' end
Util.JsonDecode=function(p) return p end
local admin=false
local function readStub(path) return files[path] end
local c2=dofile('server/RacePrep/RaceControl.lua').new({rules=function() return {} end,path=tmp,read=readStub,
 canEdit=function() return admin end})
local saved=io.open
c2.snapshot({phase='none',participants={},level='/levels/mosport/info.json'})
local tr=c2.state.track
assert(tr and tr.level=='mosport' and tr.rubber.enabled==false and tr.rubber.lapsToFull==40,'defaults: off, 40 car-laps')
assert(c2.addRubberCells(3,'1,2,3,1,1,0')==0,'no build-up while rubber is off')
RacePrepTrackSet(3,{rubber={enabled=true}});assert(c2.state.track.rubber.enabled==false,'needs SetConfig')
admin=true
RacePrepTrackSet(3,{rubber={enabled=true,buildKm=10,lapsToFull=40}})
assert(c2.addRubberCells(3,'1,2,3,10,1,0')==1)
assert(c2.addRubberCells(3,'1,2,3,10,1,0')==0,'rate limited')
c2.snapshot({raceID=1,runID='200',phase='race',participants={},level='mosport'})
assert(c2.rubberMap.map('mosport')['1:2'].a==10 and c2.state.rubber.enabled,'spatial cells persist')
c2.snapshot({phase='none',participants={},level='mosport'})
assert(c2.rubberMap.map('mosport')['1:2'].a==10,'rubber stays after the race')
RacePrepTrackSet(3,{amount=1});assert(c2.rubberMap.map('mosport')['1:2'].a==c2.state.rubber.perLap*40,'full rubber')
RacePrepTrackSet(3,{amount=.6});assert(math.abs(c2.rubberMap.map('mosport')['1:2'].a-c2.state.rubber.perLap*40*.6)<1e-9,'any level')
RacePrepTrackSet(3,{amount='clean'});assert(c2.rubberMap.count('mosport')==0,'clean means no rubber')
RacePrepTrackSet(3,{amount=5,rubber={buildKm=-3,lapsToFull=401}});assert(c2.state.rubber.lapsToFull==40 and c2.state.track.rubber.buildKm==10,'bounds; old settings retained')
RacePrepTrackSet(3,{wind={enabled=true,speedKmh=30,direction=180}})
assert(c2.state.track.wind.enabled and c2.state.track.wind.speedKmh==30 and c2.state.track.wind.gustKmh==5,'wind per map')
c2.snapshot({phase='none',participants={},level='other'})
assert(c2.state.track.level=='other' and not c2.state.track.wind.enabled and not c2.state.rubber.enabled,'another map has its own settings')
-- migration from 1.5.1-1.5.3 rubber.json
local oldRubber={levels={mosport={metres=0,full=true},spa={metres=15000}}}
local c3=dofile('server/RacePrep/RaceControl.lua').new({rules=function() return {} end,path=tmp,read=function(path)
 if path:find('rubber.json',1,true) then return oldRubber end end})
c3.snapshot({phase='none',participants={},level='spa'})
assert(c3.state.track.rubber.initial==20 and c3.state.track.rubber.lapsToFull==40,'legacy file readable with new defaults')
os.execute('rm -rf '..tmp)
Util.JsonEncode=function(p) return p end
print('PASS: track settings per map: rubber stays, admin set/clean/full, build-up only when on, wind, migration')
print('PASS: yellow debounce, moving clear, stale telemetry reset')

jsonEncode=function(p) return p end;jsonDecode=function(p) return p end
local sent,freeze={},0
TriggerServerEvent=function(e,p) sent[#sent+1]={event=e,payload=p} end;package.loaded['ge/extensions/raceprep/net']={send=TriggerServerEvent}
local pos={x=0,y=0,z=0}
local car={getPosition=function() return pos end}
car.getID=function() return 10 end;car.queueLuaCommand=function() end;car.getVelocity=function() return {length=function() return 0 end} end
BJI_Veh={getCurrentVehicleOwn=function() return car end,freeze=function(v) assert(v==false);freeze=freeze+1 end}
local race={raceID=1,state=2,STATES={RACE=2},race={startTime=10000},isParticipant=function() return true end}
BJI_Scenario={TYPES={RACE_MULTI=1},get=function() return race end}
bjiRacePrep={getRules=function() return rules end}
local now=5000;GetCurrentTimeMillis=function() return now end
local D=require('ge/extensions/raceprep/director')
D.onState({runID='102',raceID=1,falseStarts={}})
rules.startType='standing';D.update(0);assertEq(D.lights.count,1);assertEq(freeze,1)
pos.x=.5;now=6000;D.update(1);assert(not D.falseStart)
pos.x=1;now=7000;D.update(2);assert(not D.falseStart,'rolling without throttle (slope) is not a jump start')
D.onTelemetry(10,{throttle=1,damage=0});D.update(2.1);assert(D.falseStart)
local n=0;for _,e in ipairs(sent) do if e.event=='RacePrepControlEvent' then n=n+1 end end
D.update(3);n=0;for _,e in ipairs(sent) do if e.event=='RacePrepControlEvent' and e.payload.kind=='falseStart' then n=n+1 end end;assertEq(n,1)
now=10000;D.update(4);assertEq(D.lights.phase,'green')
now=14000;D.update(5);assert(D.lights==nil)
-- contact verdicts from the cars' positions/velocities half a second before
local function hist(me,other) return {{t=0,cars={[10]={owner=0,pos=me[1],vel=me[2]},[11]={owner=1,pos=other[1],vel=other[2]}}}} end
local v=function(x,y) return {x=x,y=y,z=0} end
assertEq(D.judgeContact(10,hist({v(0,0),v(0,30)},{v(0,8),v(0,25)}),1),'me') -- I rear-end the car ahead
assertEq(D.judgeContact(10,hist({v(0,0),v(0,25)},{v(0,-8),v(0,30)}),1),'other') -- rear-ended by the car behind
assertEq(D.judgeContact(10,hist({v(0,0),v(0,30)},{v(4,0),v(0,30)}),1),'shared') -- side by side, nobody turning in
assertEq(D.judgeContact(10,hist({v(0,0),v(0,30)},{v(4,0),v(-6,30)}),1),'other') -- the other car turns into me
assertEq(D.judgeContact(10,hist({v(0,0),v(0,30)},{v(40,0),v(0,30)}),1),'self') -- nobody near: wall or spin
print('PASS: contact verdicts (rear-end, side-swipe, side by side, alone)')
print('PASS: start lights, movement threshold, one incident, rolling exclusion, authority and additive penalties')
