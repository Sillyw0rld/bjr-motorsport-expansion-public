-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Host=require('ge/extensions/raceprep/frontend').host()
local Tracker=require('ge/extensions/raceprep/bjr/lapTracker')
local Ghost=require('ge/extensions/raceprep/bjr/rivalsGhost')
local M={}
local data,tracker,vehicle,revision,trace,lastSample,lastLapStart,pbTrace,pbTime
local view={active=false}
local markerSignature
local nextUpdate=0
local ghosts={target=true,best=true} -- the player's choice, sent by the UI
local function layer() return shape and shape.layer and shape.layer('raceprepRivals') end
local function send(p) Host.send('RacePrepRivals',p) end
local function finite(n,lo,hi) return type(n)=='number' and n==n and n>=lo and n<=hi end
local function validTrack(track)
 if type(track)~='table' or type(track.gates)~='table' or #track.gates<2 or #track.gates>1024 then return false end
 for _,g in ipairs(track.gates) do
  if type(g)~='table' or type(g.pos)~='table' or type(g.dir)~='table' then return false end
  for _,axis in ipairs({'x','y','z'}) do if not finite(g.pos[axis],-1000000,1000000) or not finite(g.dir[axis],-1000000,1000000) then return false end end
  if g.dir.x*g.dir.x+g.dir.y*g.dir.y<1e-10 or not finite(g.width or 10,.1,10000) or not finite(g.height or 5,.1,10000) then return false end
 end
 return true
end
local function validReference(reference,gates)
 if type(reference)~='table' or #reference<5 or #reference>2400 then return false end
 local previous=-1
 for _,p in ipairs(reference) do
  if type(p)~='table' or not finite(p.t,0,1800000) or p.t<=previous or not finite(p.g,1,gates) or p.g%1~=0 or
   not finite(p.x,-1000000,1000000) or not finite(p.y,-1000000,1000000) or not finite(p.z,-100000,100000) then return false end
  previous=p.t
 end
 return true
end
function M.stop()
 if data then send{action='stop',id=data.id} end
 local draw=layer();if draw then draw.reset() end;markerSignature=nil
 data=nil;tracker=nil;trace={};view={active=false}
end
function M.receive(p)
 if p.stopped then data=nil;M.stop();return end
 if p.error then view.message=p.error;if data then M.stop();view.message=p.error end;return end
 if p.track then
  if data then M.stop() end
  local v=Host.vehicle();if not v then return end
  if not validTrack(p.track) then view.message='This layout has unusable gate geometry; choose another challenge.';send{action='stop',id=p.id};return end
  local ok,built=pcall(Tracker.new,p.track)
  if not ok or not built:valid() then view.message='This layout cannot be timed; choose another challenge.';send{action='stop',id=p.id};return end
  if not validReference(p.reference,#p.track.gates) then p.reference=nil end
  data=p;nextUpdate=0;tracker=built;vehicle=v:getID()
  local d=core_vehicle_manager.getVehicleData(vehicle);revision=d and d.vdata
  trace={};lastSample=-1;lastLapStart=nil;pbTrace=nil;pbTime=nil
  view={active=true,completedLaps=0,id=p.id,raceName=p.raceName,target=p.target,referenceKind=p.reference and 'target' or nil,message='Drive to the start line. Start marker shown on the map by BJR race selection.'}
 elseif data and p.id==data.id then
  if p.lapToken then data.lapToken=p.lapToken end
  view.saveMessage=p.message;view.savedLap=p.lap
  if p.lap and p.lap.verified then view.lastLap=p.lap end
 end
end
function M.cut(id) if data and tracker and id==vehicle then tracker:cut() end end
function M.resetLap(id)
 if data and id==vehicle then tracker=Tracker.new(data.track);trace={};lastLapStart=nil;view.delta=nil;view.message='Reset: cross the start line for a new lap.' end
end
local function components(v,n)
 if type(v)=='table' then return v end
 if type(v)~='string' then return end
 local a={};for token in v:gmatch('[^,%s]+') do local x=tonumber(token);if not x then return end;a[#a+1]=x end
 if #a==n then return {x=a[1],y=a[2],z=a[3],w=a[4]} end
end
function M.goToStart()
 local v=Host.vehicle();local starts=data and data.track.startPositions
 if not data or not v or not starts or #starts==0 then return false,'This layout has no usable grid position. Drive to its first gate.' end
 local slot=data.challengeType=='raceDistance' and starts[1] or starts[((Host.playerID() or 0)%#starts)+1]
 local pos,dir=components(slot.pos,3),components(slot.dir,3)
 if not dir then local rot=components(slot.rot,4);if rot then dir=require('ge/extensions/raceprep/lapTracker').forward(rot) end end
 if not pos or not dir or not beamjoy_vehicles or not beamjoy_vehicles.setVehiclePositionRotation then return false,'Start position is unavailable.' end
 beamjoy_vehicles.setVehiclePositionRotation(v,vec3(pos),vec3(dir),vec3(0,0,1),{cling=false,safe=false})
 M.resetLap(v:getID());return true
end
local function markers()
 local draw=layer();if not draw or not data then return end
 local hidden=beamjoy_markerSettings and beamjoy_markerSettings.hideActivities
 local key=tostring(tracker.state)..':'..tostring(tracker.last)..':'..tostring(hidden)
 if key==markerSignature then return end;markerSignature=key;draw.reset()
 if hidden or type(BJColor)~='function' then return end
 local trap=data.options and data.options.trap
 if trap then
  local pos=vec3(trap.x,trap.y,trap.z);local side=vec3(-trap.dy,trap.dx,0)*trap.width/2
  draw.addLine(pos-side,.15,pos+side,.15,BJColor(1,.75,.1,.8));draw.addText('Speed trap',pos+vec3(0,0,2),BJColor(1,1,1,1),BJColor(0,0,0,.5),true)
 end
 local ids={};local race=data.track
 if tracker.state=='out' then for i,g in ipairs(race.gates) do if (g.step or i)==1 then ids[#ids+1]=i end end
 elseif not race.branchingEnabled then ids[1]=(tracker.last%#race.gates)+1
 else
  for i,g in ipairs(race.gates) do for _,parent in ipairs(g.parents or {}) do if parent==tracker.last then ids[#ids+1]=i;break end end end
  if #ids==0 and race.loopable then for i,g in ipairs(race.gates) do if (g.step or i)==1 then ids[#ids+1]=i end end end
 end
 for n,id in ipairs(ids) do
  if n>32 then break end
  local gate=race.gates[id];local pos=vec3(gate.pos);local dir=vec3(gate.dir):normalized();local side=dir:cross(vec3(0,0,1))*(gate.width or 10)/2
  for _,p in ipairs({pos-side,pos+side}) do draw.addLine(p,.12,p+vec3(0,0,gate.height or 5),.12,BJColor(1,.55,.15,.8)) end
  draw.addText('Rivals · Gate '..id,pos+vec3(0,0,1),BJColor(1,1,1,1),BJColor(0,0,0,.5),true)
 end
end
function M.rules() return data and data.rules end
function M.active() return data~=nil end
local function referenceTime(reference,p,gate)
 local best,at=math.huge,nil
 for i=2,#(reference or {}) do
  local a,b=reference[i-1],reference[i]
  if a.g==gate and b.g==gate then
   local x,y,z=b.x-a.x,b.y-a.y,b.z-a.z;local len=x*x+y*y+z*z
   if len>.01 then
    local f=math.max(0,math.min(1,((p.x-a.x)*x+(p.y-a.y)*y+(p.z-a.z)*z)/len))
    local d=(p.x-a.x-x*f)^2+(p.y-a.y-y*f)^2+(p.z-a.z-z*f)^2
    if d<best then best=d;at=a.t+(b.t-a.t)*f end
   end
  end
 end
 if best<=400 then return at end
end
function M.update(now)
 if not data then return end
 if now<nextUpdate then return end;nextUpdate=now+100
 local v=Host.vehicle();local d=v and core_vehicle_manager.getVehicleData(v:getID())
 local level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()
 local r=beamjoy_raceRunner
 local practice=package.loaded['ge/extensions/raceprep/session']
 if (practice and practice.active()) or not Host.ready() or not v or v:getID()~=vehicle or v:getJBeamFilename()~=data.model or not d or d.vdata~=revision or level~=data.level or
  (r and (r.session or r.spectatingSession)) then M.stop();view.message='Rivals stopped: car, track or activity changed.';return end

 local p=v:getPosition();local lap=tracker:update(now,p)
 markers()
 if lap then
  local savedTrace=trace
  if lap.valid and (not pbTime or lap.time<pbTime) then pbTime=lap.time;pbTrace=savedTrace end
  -- the server times the lap from its own position samples; the trace stays here for the live delta
  send{action='lap',id=data.id,lapToken=data.lapToken,time=lap.time,cuts=lap.cuts or 0,valid=lap.valid==true}
  view.lastLap={time=lap.time,valid=lap.valid};view.completedLaps=(view.completedLaps or 0)+1;view.personalBest=pbTime
 end
 if tracker.lapStart~=lastLapStart then trace={};lastSample=-1;lastLapStart=tracker.lapStart end
 local elapsed=tracker:current(now);view.currentLap=elapsed;view.valid=tracker.state=='lap' and tracker.cuts==0 and not tracker.void
 if elapsed and elapsed>=0 and now-lastSample>=200 and #trace<2400 then
  trace[#trace+1]={t=math.floor(elapsed),g=tracker.last,x=p.x,y=p.y,z=p.z};lastSample=now
 end
 local ref=data.reference or pbTrace
 local refTime=elapsed and referenceTime(ref,p,tracker.last)
 view.referenceKind=data.reference and 'target' or pbTrace and 'personal' or nil
 view.delta=refTime and elapsed-refTime or nil
 view.message=tracker.state=='lap' and (not ref and 'Recording a reference lap; live delta starts after your first clean lap.' or nil) or 'Cross the start line to begin timing.'
end
function M.setGhosts(p)
 if type(p)~='table' then return end
 ghosts.target=p.target~=false;ghosts.best=p.best~=false
end
--- every frame: the target's and your best lap's ghosts at this moment of the lap
function M.draw(now)
 if not data or not tracker or (beamjoy_markerSettings and beamjoy_markerSettings.hideActivities) then return end
 local elapsed=tracker:current(now);local v=elapsed and Host.vehicle()
 if not v or v:getID()~=vehicle then return end
 local list={}
 if ghosts.target and data.reference then
  list[#list+1]={trace=data.reference,t=elapsed,label=tostring(data.target and data.target.name or 'Target')..' · target',color={1,.55,.15},alpha=.35}
 end
 if ghosts.best and pbTrace then list[#list+1]={trace=pbTrace,t=elapsed,label='Your best',color={.45,.75,1},alpha=.22} end
 if #list>0 then Ghost.draw(list,v:getPosition()) end
end
function M.view() return view end
return M
