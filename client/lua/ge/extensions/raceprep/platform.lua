-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Boundary for the original BeamJoy and BeamJoy-Revived hosts. Return small
-- adapters to shared logic, not synthetic BJI globals in the game's VM.
local P={}
local H
local function bjr() return rawget(_G,'raceprepBJR')~=nil end
local function host() H=H or require('ge/extensions/raceprep/bjr/host');return H end
local context,vehicles,scenario,message={},{},{},{}
local snapshot
local function normalRace()
 local h=host();local r,s=h.race();if not r then return end
 local runner=beamjoy_raceRunner
 local old=snapshot
 if not old or old.native~=s.id then old={native=s.id,STATES={GRID=1,RACE=2},raceID=s.raceId};snapshot=old end
 old.state=s.state=='GRID' and 1 or (s.state=='COUNTDOWN' or s.state=='RACE') and 2 or nil
 if not old.state then return end
 local now=GetCurrentTimeMillis and GetCurrentTimeMillis() or 0
 old.race=old.race or {}
 local start=h.raceStartMs(runner)
 if s.state=='COUNTDOWN' then start=runner.countdownStartMs and runner.countdownStartMs+(runner.countdownTotal or 0)*1000 or old.race.startTime or now end
 old.race.startTime=start or old.race.startTime or now
 old.race.settings={laps=s.settings.laps or 1}
 old.race.leaderboard={}
 for _,p in pairs(s.participants or {}) do
  old.race.leaderboard[#old.race.leaderboard+1]={playerID=p.playerID,lap=p.currentLap or 1,wp=p.currentGate or 0,
   time=p.lastElapsedMs or p.elapsedMs,finished=p.finished,dnf=p.dnf}
 end
 old.grid={participants={}}
 local grid={};for _,p in pairs(s.participants or {}) do grid[#grid+1]=p end
 table.sort(grid,function(a,b) return (a.gridSlot or a.joinIndex or 999)<(b.gridSlot or b.joinIndex or 999) end)
 for _,p in ipairs(grid) do old.grid.participants[#old.grid.participants+1]=p.playerID end
 old.isRaceStarted=function() return s.state=="RACE" end
 old.race.lap=(h.participant() or {}).currentLap or 1
 old.race.waypoint=(h.participant() or {}).currentGate or 0
 old.race.raceData={wpPerLap=#(r.gates or {})}
 old.raceName=r.name;old.getRace=function() return P.track(r) end
 old.isParticipant=function() return h.participant()~=nil end
 old.isFinished=function() return (h.participant() or {}).finished==true end
 old.isEliminated=function() return (h.participant() or {}).dnf==true end
 return old
end
function P.track(r)
 if not r then return end
 local groups={};local maxStep=0
 for i,g in ipairs(r.gates or {}) do
  local step=tonumber(g.step) or i;groups[step]=groups[step] or {}
  groups[step][#groups[step]+1]={pos=g.pos,dir=g.dir,radius=(g.width or 10)/2,height=g.height or 10,name='Gate '..i}
  maxStep=math.max(maxStep,step)
 end
 local steps={}
 for i=1,maxStep do if groups[i] then steps[#steps+1]=groups[i] end end
 -- The shared timer ends laps at its last step. BJR loopable races end at
 -- their first gate; rotate the groups so the same physical line is used.
 if r.loopable and #steps>1 then local first=table.remove(steps,1);steps[#steps+1]=first end
 return {id=r.id,name=r.name,steps=steps,startPositions=r.startPositions,loopable=r.loopable,sectorCount=r.sectorCount}
end
setmetatable(context,{__index=function(_,key)
 if key=='User' then return {playerID=host().playerID()} end
 if key=='Players' then
  local out={}
  for _,p in pairs(beamjoy_players and beamjoy_players.players or {}) do if p.playerID then out[p.playerID]=p end end
  return out
 end
end})
vehicles.getCurrentVehicleOwn=function() return host().vehicle() end
vehicles.isVehicleOwn=function(id) return host().own(id) end
vehicles.freeze=function(value)
 local v=host().vehicle();if v then v:queueLuaCommand('controller.setFreeze('..(value and '1' or '0')..')') end
end
vehicles.setPositionRotation=function(pos,rot)
 local v=host().vehicle()
 if v and beamjoy_vehicles then
  local f=require('ge/extensions/raceprep/lapTracker').forward(rot)
  beamjoy_vehicles.setVehiclePositionRotation(v,pos,vec3(f.x,f.y,f.z),vec3(0,0,1),{cling=false,safe=false})
 end
end
scenario.TYPES={RACE_MULTI='race'}
scenario.get=function() return normalRace() end
scenario.isFreeroam=function() return host().session()==nil end
message.flash=function(_,text) host().notice(text) end
function P.get(name)
 if not bjr() then return rawget(_G,name) end
 if name=='BJI' then return {CLIENT_READY=host().ready()} end
 if name=='BJI_Context' then return context end
 if name=='BJI_Veh' then return vehicles end
 if name=='BJI_Scenario' then return scenario end
 if name=='BJI_Message' then return message end
 return rawget(_G,name)
end
function P.isBJR() return bjr() end
return P
