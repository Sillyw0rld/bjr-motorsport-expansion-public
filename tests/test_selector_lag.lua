-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- Spawn vehicle lag (2026-10-17): building selector tiles compiled each
-- rated config's jbeam on every getModel call. Now never during tile
-- building: resolved once per config in the background, then cached.
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
local identity=require('ge/extensions/raceprep/ratingIdentity')
local parts={['/main']='car_body',['/main/engine']='engine_x'}
local key=identity.key('m','c',parts)
local loads=0
package.loaded['jbeam/loader']={loadJbeamOnlyConfig=function() loads=loads+1;return {partsTree={chosenPartName='car_body',children={engine={chosenPartName='engine_x',children={}}}}} end}
jsonReadFile=function(path)
 if path:find('ratings%-seed') then return {entries={},constants={}} end
 if path:find('%.pc$') then return {parts={}} end
 return nil
end
readFile=function() return '{}' end
local decoded={full={entries={[key]={model='m',config='c',pi=600,class='B',source='computed',parts=parts}},constants={},vehicles={}}}
jsonDecode=function(s) return decoded[s] or {models={}} end
identity.flatten=function() return parts end -- the stub tree flattens to these parts
local model={model={key='m',default_pc='c',Name='Model M'},configs={c={key='c',model_key='m',Name='Config C'}}}
core_vehicles={getModel=function() return model end}
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
R.onRatings('full')
pcall(R.decorateSelector)
for _=1,50 do core_vehicles.getModel('m') end
assert(loads==0,'no jbeam compile while the selector builds tiles (was once per getModel call)')
assert(R.resolvePending()==1,'the config waits in the background queue once')
assert(R.resolveNext()==true and loads==1)
core_vehicles.getModel('m')
assert(model.configs.c.Name:find('%[B 600%]'),'label appears once resolved: '..model.configs.c.Name)
for _=1,50 do core_vehicles.getModel('m') end
assert(loads==1 and R.resolvePending()==0,'cached: never compiled again')
print('PASS: selector tiles never compile jbeam; each config resolved once in the background')

-- F3: spawning a car whose rating is already known publishes it without
-- running synchronous loadJbeam or raceprepRating.collect; onStatic only
-- bumps catalogRevision when entries actually change.
do
 local fullLoads,queuedCmds,published=0,{},{}
 package.loaded['jbeam/loader'].loadJbeam=function() fullLoads=fullLoads+1;return {vdata={nodes={},wheels={},powertrain={}}} end
 core_vehicle_manager={getVehicleData=function(id)
  return {vdata={model='m',activeParts=parts},config={partConfigFilename='vehicles/m/c.pc'}}
 end}
 getObjectByID=function(id) return {getID=function() return id end,queueLuaCommand=function(_,cmd) queuedCmds[#queuedCmds+1]=cmd end} end
 MPVehicleGE={getVehicleByGameID=function(id) return {isLocal=true,serverVehicleString='1-'..id,ownerID=1} end}
 jsonEncode=function(t) return t end
 TriggerServerEvent=function(ev,payload) published[#published+1]={ev=ev,payload=payload} end
 package.loaded['ge/extensions/raceprep/net']={send=TriggerServerEvent}
 R.onVehicleSpawned(10)
 local revBefore=R.catalogRevision
 R.onUpdate(1.5)
 assert(fullLoads==0,'known rating: no synchronous loadJbeam on spawn')
 for _,cmd in ipairs(queuedCmds) do assert(not cmd:find('raceprepRating%.collect'),'known rating: no collect command on spawn') end
 assert(#published==1 and published[1].ev=='RacePrepComputedRating' and published[1].payload.key and published[1].payload.parts==nil,'known rating published immediately (short report by key)')
 R.onStatic(10,'stale-token',{mass=1200})
 assert(R.catalogRevision==revBefore,'catalogRevision not bumped when entries do not change')
 print('PASS: spawning a known car publishes its rating without loadJbeam/collect; catalogRevision guarded')
end

-- 2026-10-18 zlib warnings: a rating the server never confirms (e.g. a tuning
-- share that comes back as a slightly different float) re-sent the full parts
-- list every 5 s. An identical report now goes out at most once a minute.
do
 local published={}
 TriggerServerEvent=function(ev,payload) if ev=='RacePrepComputedRating' then published[#published+1]=payload end end
 AddEventHandler=function() end
 BJI={CLIENT_READY=true}
 for _=1,11 do R.onUpdate(5.1) end -- 56 s, server never confirms
 assert(#published<=1,'unconfirmed rating re-sent '..#published..' times in 56 s (limit: once a minute)')
 for _=1,2 do R.onUpdate(5.1) end -- past 60 s
 assert(#published<=2,'at most one more report after a minute')
 print('PASS: unconfirmed rating reports limited to one a minute (no 5 s parts-list resend)')
end
