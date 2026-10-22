-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- Race control follows BeamJoy's synchronized start time; never starts a race itself.
local D={data=nil,lights=nil}
local anchorVehicle
local key,anchor,reported,nextRequest=nil,nil,false,0
local clockNow,nextTelemetry,telemetryVehicle=0,0,nil
local lastRubberClock=0
D.telemetry=nil
D.hazards={}
local function race()
 local BJI_Scenario=Platform.get("BJI_Scenario")
 local s=Platform.get("BJI_Scenario")
 return s and s.TYPES and s.get(s.TYPES.RACE_MULTI)
end
local function send(event,p)
 require('ge/extensions/raceprep/net').send(event,jsonEncode(p))
end
D.onState=function(json)
 local ok,p=pcall(jsonDecode,json)
 if ok and type(p)=='table' then
  D.data=p;D.receivedAt=clockNow
  D.hazards=p.hazards or {}
  local R=require('ge/extensions/raceprep/results')
  if R.onControl then R.onControl(p) end
 end
end
-- Contacts: when my car takes a hard hit (damage jump between telemetry
-- samples), look at where the race cars were ~0.5 s before. No car within
-- 15 m: my own incident ("self"). Otherwise the car moving towards the other
-- faster is at fault ("me" / "other"); too close to call: "shared". The
-- server counts it once per pair; the car that was hit loses nothing.
local HIT_DAMAGE,HISTORY_S=5000,1.5
local history={} -- {t, cars = {[gameVehID] = {owner, pos, vel}}}
local lastDamage,lastContactAt=nil,-1e9
local function vec(p) return {x=p.x,y=p.y,z=p.z} end
local function sampleCars(r,clock)
 local BJI_Veh=Platform.get("BJI_Veh")
 if history[#history] and clock-history[#history].t<.1 then return end
 local me=BJI_Veh and BJI_Veh.getCurrentVehicleOwn()
 if not me or not MPVehicleGE or not MPVehicleGE.getVehicles then return end
 local mp=me:getPosition()
 local members={}
 for _,pid in ipairs(r.grid and r.grid.participants or {}) do members[pid]=true end
 local cars={}
 for _,v in pairs(MPVehicleGE.getVehicles() or {}) do
  local obj=v.gameVehicleID and be:getObjectByID(v.gameVehicleID)
  if obj and members[v.ownerID] then
   local p=obj:getPosition()
   if obj:getID()==me:getID() or (p.x-mp.x)^2+(p.y-mp.y)^2<=60^2 then
    cars[obj:getID()]={owner=v.ownerID,pos=vec(p),vel=vec(obj:getVelocity())}
   end
  end
 end
 history[#history+1]={t=clock,cars=cars}
 while history[1] and clock-history[1].t>HISTORY_S do table.remove(history,1) end
end
D.judgeContact=function(myID,hist,now,nowCars)
 local before=hist[1]
 for _,h in ipairs(hist) do if now-h.t>=.5 then before=h end end
 local mine=before and before.cars[myID]
 if not mine then return 'self',nil end
 local best,bestD
 for id,c in pairs(before.cars) do
  if id~=myID then
   local dx,dy,dz=c.pos.x-mine.pos.x,c.pos.y-mine.pos.y,c.pos.z-mine.pos.z
   local d=math.sqrt(dx*dx+dy*dy+dz*dz)
   local near=true
   local cur=nowCars and nowCars[id]
   if cur and nowCars[myID] then
    local m=nowCars[myID].pos
    near=(cur.pos.x-m.x)^2+(cur.pos.y-m.y)^2<=10^2
   end
   if d<=15 and near and (not bestD or d<bestD) then best,bestD=id,d end
  end
 end
 if not best then return 'self',nil end
 local o=before.cars[best]
 local rx,ry,rz=o.pos.x-mine.pos.x,o.pos.y-mine.pos.y,o.pos.z-mine.pos.z
 local d=math.max(.1,math.sqrt(rx*rx+ry*ry+rz*rz))
 local myClosing=(mine.vel.x*rx+mine.vel.y*ry+mine.vel.z*rz)/d
 local otherClosing=-(o.vel.x*rx+o.vel.y*ry+o.vel.z*rz)/d
 if myClosing-otherClosing>1.5 then return 'me',o.owner end
 if otherClosing-myClosing>1.5 then return 'other',o.owner end
 return 'shared',o.owner
end
D.onTelemetry=function(id,p)
 local BJI_Veh=Platform.get("BJI_Veh")
 local v=BJI_Veh and BJI_Veh.getCurrentVehicleOwn()
 if not (v and v:getID()==id and type(p)=='table') then return end
 D.telemetry=p;D.telemetryAt=clockNow
 local damage=tonumber(p.damage) or 0
 local jump=lastDamage and damage-lastDamage or 0
 lastDamage=damage
 local r=race();local state=D.data
 if jump<=HIT_DAMAGE or clockNow-lastContactAt<4 or not r or not state or not state.runID then return end
 local now=GetCurrentTimeMillis and GetCurrentTimeMillis() or 0
 if not (r.race and r.race.startTime and now>=r.race.startTime) then return end
 lastContactAt=clockNow
 local latest=history[#history]
 local verdict,other=D.judgeContact(id,history,clockNow,latest and latest.cars)
 send('RacePrepControlEvent',{runID=state.runID,kind='contact',verdict=verdict,other=other})
end
local function disableTelemetry()
 if telemetryVehicle then
  local v=be and be:getObjectByID(telemetryVehicle)
  if v then v:queueLuaCommand('if raceprepRaceTelemetry then raceprepRaceTelemetry.disable() end') end
 end
 telemetryVehicle=nil;D.telemetry=nil
end
local function telemetry(r,clock)
 local BJI_Veh=Platform.get("BJI_Veh")
 local state=D.data
 if not state or tostring(state.raceID)~=tostring(r.raceID) or not state.runID or not (r.isParticipant and r.isParticipant()) then return end
 if (r.isFinished and r.isFinished()) or (r.isEliminated and r.isEliminated()) then return end
 local v=BJI_Veh and BJI_Veh.getCurrentVehicleOwn()
 if not v or clock<nextTelemetry then return end
 nextTelemetry=clock+.5
 if telemetryVehicle~=v:getID() then disableTelemetry();telemetryVehicle=v:getID() end
 v:queueLuaCommand('extensions.load("raceprepRaceTelemetry") if raceprepRaceTelemetry then raceprepRaceTelemetry.enable() end')
 local t=D.telemetry
 if not t or clock-(D.telemetryAt or 0)>2 then return end
 local p,vel=v:getPosition(),v:getVelocity()
 send('RacePrepControlEvent',{runID=state.runID,kind='telemetry',onTrack=t.onTrack==true,damage=t.damage,
  position={x=p.x,y=p.y,z=p.z},speed=vel:length(),lap=r.race.lap or 1,wp=r.race.waypoint or 0,
  checkpoints=r.race.raceData and r.race.raceData.wpPerLap or 1})
end
D.yellow=function()
 local BJI_Veh=Platform.get("BJI_Veh")
 local r=race()
 if not r or not r.STATES or r.state~=r.STATES.RACE then return nil end
 local s=D.data
 if s and s.fullCourseYellow then return 'FULL COURSE YELLOW - slow down, no overtaking' end
 -- local hazard yellows are for the drivers in this race: spectators (no
 -- own car, or a car not in the race) saw "hazards reported" or yellows from
 -- their own position for every stopped car on the map
 if not (r.isParticipant and r.isParticipant()) then return nil end
 local v=BJI_Veh and BJI_Veh.getCurrentVehicleOwn()
 if not v then return nil end
 local p=v:getPosition()
 for _,h in pairs(D.hazards) do
  local q=h.position
  if q and math.abs(p.z-q.z)<=12 and (p.x-q.x)^2+(p.y-q.y)^2<=200^2 then return 'YELLOW FLAG - stopped car ahead, slow down, no overtaking' end
 end
end
D.show=false
D.championship=function(action,p) p=p or {};p.action=action;send('RacePrepChampionship',p) end
D.adminYellow=function(value) send('RacePrepYellow',{enabled=value}) end
-- admin: change the current map's track settings (see RaceControl.setTrack)
D.setTrack=function(p) send('RacePrepTrackSet',p) end
D.update=function(clock)
 local BJI_Veh=Platform.get("BJI_Veh")
 clockNow=clock
 local r=race()
 local live=r and r.STATES and (r.state==r.STATES.GRID or r.state==r.STATES.RACE) and
  clock-(D.receivedAt or -100)<6 and D.data or nil
 local rubber=require('ge/extensions/raceprep/rubberLine')
 rubber.configure(D.data and D.data.rubber,clock)
 rubber.update(math.max(0,math.min(.2,clock-lastRubberClock)))
 lastRubberClock=clock
 require("ge/extensions/raceprep/raceEnvironment").update(D.data and D.data.track,clock,D.receivedAt)
 require("ge/extensions/raceprep/weather").update(D.data and D.data.track,clock)
 local active=r and r.STATES and r.state==r.STATES.RACE and r.race and r.race.startTime
 if not active then
  disableTelemetry();D.hazards={};D.lights=nil;key=nil;anchor=nil;reported=false;history={};lastDamage=nil;D.falseStart=nil
  -- outside races the server sends only changes; ask now and then
  if clock>=nextRequest then send('RacePrepGetControl',{});nextRequest=clock+(D.data and 30 or 5) end
  return
 end
 local k=tostring(r.raceID)..':'..tostring(r.race.startTime)
 if k~=key then key=k;anchor=nil;reported=false;nextRequest=0;D.falseStart=nil end
 if clock>=nextRequest then send('RacePrepGetControl',{});nextRequest=clock+2 end
 telemetry(r,clock)
 pcall(sampleCars,r,clock)
 local rules=bjiRacePrep.getRules(r.raceID)
 if not rules.startLights then D.lights=nil;return end
 local now=GetCurrentTimeMillis and GetCurrentTimeMillis() or clock*1000
 local remaining=r.race.startTime-now
 if rules.startType=='rolling' then
  local rolling=bjiRacePrep.rolling
  D.lights={phase=remaining>0 and 'red' or (rolling and rolling.phase=='green' and 'green' or 'formation'),
   count=math.max(0,math.min(5,5-math.ceil(remaining/1000)+1)),remaining=remaining}
  return
 end
 D.lights={phase=remaining>0 and 'red' or 'green',count=math.max(0,math.min(5,6-math.ceil(remaining/1000))),remaining=remaining}
 if remaining < -3000 then D.lights=nil end
 if not (r.isParticipant and r.isParticipant()) or (r.isFinished and r.isFinished()) then return end
 local v=BJI_Veh and BJI_Veh.getCurrentVehicleOwn()
 if not v or remaining>5000 or remaining<=0 then return end
 local p=v:getPosition()
 if not anchor or anchorVehicle~=v:getID() then anchor={x=p.x,y=p.y};anchorVehicle=v:getID();D.falseStart=nil end
 -- This deliberate release makes a jump start physically possible. BeamJoy
 -- still owns the countdown, waypoints and official start timer.
 if BJI_Veh.freeze then BJI_Veh.freeze(false) end
 local dx,dy=p.x-anchor.x,p.y-anchor.y
 if dx*dx+dy*dy>3600 then anchor={x=p.x,y=p.y};return end -- reset/teleport is not a jump-start sample
 local t=D.telemetry
 local throttle=t and clock-(D.telemetryAt or -100)<1.5 and (tonumber(t.throttle) or 0) or 0
 if not reported and throttle>.2 and dx*dx+dy*dy>(rules.falseStartTolerance or .75)^2 then
  local state=D.data
  if state and tostring(state.raceID)==tostring(r.raceID) and state.runID then
   send('RacePrepControlEvent',{runID=state.runID,kind='falseStart'})
   reported=true;D.falseStart=true
  end
 end
end
D.getRace=race
return D
