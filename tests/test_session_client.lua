-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Offline GE/vehicle integration, including expiry broadcasts and teleport formats.
package.path = 'client/lua/?.lua;' .. package.path
jsonDecode = function(x) return x end
jsonEncode = function(x) return x end
local position, commands, sent = {x=0,y=1,z=0}, {}, {}
local car = {getID=function() return 42 end, getPosition=function() return position end,
    queueLuaCommand=function(_,s) commands[#commands+1]=s end}
BJI_Veh = {getCurrentVehicleOwn=function() return car end,
    setPositionRotation=function(p,r) position=p; assert(r.w==1) end}
BJI_Context = {User={playerID=1}}
local free, map = true, 'test'
BJI_Scenario = {TYPES={},isFreeroam=function() return free end}
getCurrentLevelIdentifier = function() return map end
vec3=function(x,y,z) return {x=x,y=y,z=z} end
quat=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end
TriggerServerEvent=function(e,p) sent[#sent+1]={event=e,payload=p} end
package.loaded['ge/extensions/raceprep/net']={send=function(...) return TriggerServerEvent(...) end} -- chunking: test_net_chunks.lua
log=function(_,_,s) error(s) end
local S=require('ge/extensions/raceprep/session')
local function view(state, remaining)
    return {id='one',state=state,remaining=math.max(0,remaining),deadlineRemaining=remaining,
        trackLimits='invalid',track={level='test',steps={{{pos={x=0,y=0,z=0},radius=5}}},
            startPositions={{pos='0 1 0',rot='0,0,0,1'}}},rows={}}
end
S.update(0); S.onSession(view('running',60000)); S.update(0)
S.update(1);position={x=0,y=-1,z=0};S.update(2) -- start out-lap
assert(S.onTrackLap())
position={x=40,y=-1,z=0};S.update(10)
position={x=40,y=1,z=0};S.update(20)
position={x=0,y=1,z=0};S.update(30)
S.update(70);S.onSession(view('overtime',-10000)) -- deadline must remain 60, not 70
position={x=0,y=-1,z=0};S.update(80)
assert(#S.laps==1 and sent[#sent].payload.beforeEnd==true)
assert(not S.onTrackLap(), 'lap starting after zero must not time')
-- Joining during overtime also uses signed deadline from server.
S.onSession({id='two',state='overtime',remaining=0,deadlineRemaining=-10000,track=S.data.track,rows={}})
S.update(81);position={x=0,y=1,z=0};S.update(82)
assert(not S.onTrackLap())
free=false;assert(not S.active());S.update(83)
free=true;map='other';assert(not S.active());S.update(84)
map='test';assert(S.goToTrack());assert(position.y==1 and not S.onTrackLap())
-- be:getObjectByID fallback disables the old vehicle when limits end.
be={getObjectByID=function(_,id) assert(id==42);return car end}
S.onSession({id='active',state='running',remaining=10000,track=S.data.track,trackLimits='invalid',rows={}})
S.update(85)
S.onSession({id='three',state='running',remaining=10000,track=S.data.track,trackLimits='off',rows={}})
S.update(86);assert(commands[#commands]:find('disable',1,true))
local track={level='test',steps={{{pos={x=0,y=10,z=0},radius=5}},
    {{pos={x=0,y=20,z=0},radius=5}},{{pos={x=0,y=0,z=0},radius=5}}}}
S.onSession({id='sectors',state='running',remaining=100000,track=track,trackLimits='off',rows={}})
position={x=0,y=-1,z=0};S.update(100)
position={x=0,y=1,z=0};S.update(101)
position={x=0,y=11,z=0};S.update(111)
position={x=0,y=21,z=0};S.update(121)
position={x=0,y=-1,z=0};S.update(151)
local lap=S.lastLap
assert(lap and lap.sectors and lap.sectors[1]+lap.sectors[2]+lap.sectors[3]==lap.time)
assert(sent[#sent].event=='RacePrepLap' and sent[#sent].payload.sectors[2]==lap.sectors[2])
print('PASS: completed lap sectors retained locally and transmitted to server')
print('PASS: session expiry, late join, free roam, map mismatch, string positions, teleport reset, limits-off and object lookup')

local cuts=0
obj={getId=function() return 42 end,queueGameEngineLua=function() cuts=cuts+1 end}
wheels={wheels={}}
for i=1,4 do wheels.wheels[i]={contactMaterialID1=20,contactMaterialID2=4,downForceRaw=1} end
local limits=dofile('client/lua/vehicle/extensions/raceprepLimits.lua')
limits.enable();limits.updateGFX(.1)
wheels.wheels[1].downForceRaw=0;limits.updateGFX(.3);assert(cuts==0,'airborne wheel is not off-track contact')
wheels.wheels[1].downForceRaw=1;limits.updateGFX(.15);assert(cuts==0)
limits.updateGFX(.1);assert(cuts==1)
limits.updateGFX(2);assert(cuts==1,'one cut per excursion')
for _,w in pairs(wheels.wheels) do w.contactMaterialID1=10 end
limits.updateGFX(.5)
for _,w in pairs(wheels.wheels) do w.contactMaterialID1=19 end
limits.updateGFX(.25);assert(cuts==2)
limits.disable();limits.updateGFX(1);assert(cuts==2)
print('PASS: all-wheel cuts, airborne debounce, asphalt/kerbs, rearming, disable')
