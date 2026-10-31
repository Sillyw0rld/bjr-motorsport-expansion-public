-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Local, explicitly estimated gaps. BJR still owns ordering, intervals and laps.
-- Project onto the checkpoint-constrained route, learning the local driver's
-- line between gates. Never use Euclidean car separation or gap * speed.
local Path=require('ge/extensions/raceprep/racePath')
local G={}
local state
local SAMPLE_MS,HISTORY_MS,MAX_SAMPLES,MAX_RACERS,MAX_POINTS=100,120000,1201,64,512
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function point(p) return p and finite(p.x) and finite(p.y) and finite(p.z) end
local function copy(p) return {x=p.x,y=p.y,z=p.z} end
local function running(p)
 return p and not (p.finished or p.dnf or p.disqualified or p.disconnected or p.sittingOut or p.awaitingStart)
end
function G.reset() state=nil end
local function routeFailure(race)
 if not race then return 'Race layout unavailable' end
 if race.branchingEnabled then return 'Layout branches; route distance unavailable' end
 if #(race.gates or {})<2 then return 'Need two or more checkpoints' end
 if #race.gates>1024 then return 'Too many checkpoints for route estimate' end
end
local function build(s,race)
 local st={runID=s.id,phase=s.phaseIndex or 1,race=race,history={},resets={},status={},nextSample=0,rows={}}
 st.reason=routeFailure(race)
 if st.reason then return st end
 local cps={}
 -- BJR gate 1 is the circuit's start/finish, whereas Path's last checkpoint
 -- is its finish. Rotate identities, not progress order: gate 2..N, gate 1.
 for i=2,#race.gates do cps[#cps+1]=race.gates[i].pos end
 cps[#cps+1]=race.gates[1].pos
 for _,p in ipairs(cps) do if not point(p) then st.reason='Checkpoint positions missing';return st end end
 st.path=Path.new(nil,cps,race.gates[1].pos,#cps) -- session-only: no legacy BJI path files
 return st
end
local function progress(st,p,pos)
 local gate,lap=tonumber(p.currentGate),tonumber(p.currentLap)
 if not finite(gate) or not finite(lap) or gate%1~=0 or lap%1~=0 or gate<1 or gate>#st.race.gates or lap<1 then return nil,nil,'Checkpoint progress missing' end
 -- Repeated point-to-point runs teleport back to their start; they have no
 -- continuous shared route coordinate. Keep the official interval instead.
 if not st.race.loopable and (lap~=1 or gate==#st.race.gates) then return nil,nil,'Point-to-point distance unavailable' end
 local d,off=Path.progress(st.path,lap,gate-1,pos)
 -- The checkpoint chord is intentionally a lap-one fallback. On a curvy
 -- section it may be over 40 m from the road, but still gives a bounded,
 -- checkpoint-constrained distance estimate. Reject only clearly unrelated
 -- positions; never suppress an otherwise useful first-lap projection.
 local limit=math.max(150,(st.race.gates[gate].width or 10)*8)
 if not finite(d) or not finite(off) then return nil,nil,'Route projection unavailable' end
 if off>limit then return nil,off,string.format('Off route (%.0f m > %.0f m)',off,limit) end
 return d,off
end
local function append(st,name,p,car,now)
 local h=st.history[name]
 local function unavailable(reason,reset)
  if h and reset then st.resets[name]='History reset: '..reason end
  st.history[name]=nil;st.rows[name]=nil;st.status[name]=reason
 end
 if not running(p) then unavailable('Racer is not active',true);return end
 if not car then unavailable('No vehicle found for player ID '..tostring(p.playerID),true);return end
 if not point(car.pos) then unavailable('Vehicle position unavailable',true);return end
 local d,off,why=progress(st,p,car.pos)
 if not d then unavailable(why or 'Route projection unavailable',true);return end
 local prev=h and h[#h]
 if prev then
  local dt=now-prev.t;local travelled=Path.dist(prev.pos,car.pos)
  local reason
  if h.vehicle~=car.id then reason='vehicle changed'
  elseif h.playerID~=p.playerID then reason='player ID changed'
  elseif dt<=0 then reason='sample time went backwards'
  elseif dt>1000 then reason='position update paused'
  elseif travelled>math.max(40,dt*.2) then reason='car jumped between samples'
  elseif d<prev.d-5 then reason='route progress moved backwards'
  elseif d-prev.d>travelled*3+20 then reason='route progress jumped ahead' end
  if reason then
   st.resets[name]='History reset: '..reason
   st.history[name]=nil;st.rows[name]=nil;st.status[name]=st.resets[name];return
  end
 end
 if not h then h={vehicle=car.id,playerID=p.playerID};st.history[name]=h end
 -- Reverse driving invalidates interpolation until forward progress resumes.
 if #h>0 and d<h[#h].d then
  st.resets[name]='History reset: route progress moved backwards'
  st.history[name]=nil;st.rows[name]=nil;st.status[name]=st.resets[name];return
 end
 h[#h+1]={t=now,d=d,pos=copy(car.pos),off=off}
 while #h>MAX_SAMPLES or (#h>1 and now-h[1].t>HISTORY_MS) do table.remove(h,1) end
 local routeKey=Path.keyAfter(st.path,tonumber(p.currentLap),tonumber(p.currentGate)-1)
 st.rows[name]={distance=d,off=off,history=h,routeKey=routeKey}
 if #h<2 then st.status[name]=st.resets[name] or 'Need another position sample'
 else st.status[name]=nil;st.resets[name]=nil end
end
local function timeAt(h,target)
 if not h or #h<2 or target<h[1].d or target>h[#h].d then return end
 -- Latest crossing of a coordinate: stationary samples must not invent pace.
 for i=#h,2,-1 do
  local a,b=h[i-1],h[i]
  if a.d<=target and target<=b.d and b.d>a.d then return a.t+(b.t-a.t)*(target-a.d)/(b.d-a.d) end
 end
end
local function gap(st,front,back,now)
 local a,b=st.rows[front],st.rows[back]
 local ar,br=st.status[front],st.status[back]
 if not a or not b then
  local why=not a and (ar or 'Position unavailable for car ahead') or (br or 'Position unavailable for car behind')
  return {distanceReason=why,liveReason=why,reason=why}
 end
 local crossed=timeAt(a.history,b.distance)
 local liveReason
 if not crossed then
  liveReason=st.status[front] or (#a.history<2 and 'Need more position samples' or 'Not crossed yet')
 end
 return {distanceM=math.abs(a.distance-b.distance),liveMs=crossed and math.max(0,now-crossed) or nil,
  liveReason=liveReason,distanceOffM=math.max(a.off or 0,b.off or 0),estimated=true}
end
-- positions is a getter so the multiplayer vehicle scan is bounded to 10 Hz.
function G.update(now,s,race,positions,viewName,cuts)
 if not s or s.state~='RACE' then G.reset();return end
 if not state or state.runID~=s.id or state.phase~=(s.phaseIndex or 1) or state.race~=race then state=build(s,race) end
 local st=state
 if now<st.nextSample and now>=st.nextSample-SAMPLE_MS then return st.packet end
 st.nextSample=now+SAMPLE_MS;st.rows={};st.status={}
 local out={runID=s.id,phaseIndex=st.phase,selfName=viewName,raceName=race and race.name,reason=st.reason}
 st.packet=out
 local participants,seenPID={},{}
 for _,p in pairs(s.participants or {}) do
  if p.playerName then participants[p.playerName]=p end
  local pid=tonumber(p.playerID);if pid then seenPID[pid]=(seenPID[pid] or 0)+1 end
 end
 local cars=st.path and positions() or {}
 -- Learn only our own clean consecutive segment. The caller marks the local
 -- car; spectators cannot rewrite route geometry by following a rival.
 for _,p in pairs(participants) do
  local car=cars[tonumber(p.playerID)]
  local gate,lap=tonumber(p.currentGate),tonumber(p.currentLap)
  if st.path and car and car.localDriver and running(p) and point(car.pos) and finite(gate) and finite(lap) and gate%1==0 and lap%1==0 and gate>=1 and gate<=#st.race.gates and (st.race.loopable or (lap==1 and gate<#st.race.gates)) then
   local prev=st.localProgress
   local consecutive=prev and prev.vehicle==car.id and prev.playerID==p.playerID and
    ((lap==prev.lap and (gate==prev.gate or gate==prev.gate+1)) or
     (st.race.loopable and lap==prev.lap+1 and gate==1 and prev.gate==#st.race.gates))
   if not consecutive then st.path.recording=nil end
   local rec=st.path.recording
   if rec and prev and cuts~=prev.cuts then rec.valid=false end
   if rec and #rec.points>=MAX_POINTS then rec.valid=false;rec.last=copy(car.pos) end
   -- If we joined halfway through a segment, don't invent its missing first
   -- half. That route stays on the checkpoint approximation until next lap.
   local nearStart=Path.dist(car.pos,st.race.gates[gate].pos)<=math.max(15,st.race.gates[gate].width or 10)
   -- At most 8192 learned points across the whole route, plus the bounded
   -- in-progress segment. Long routes retain their checkpoint approximation.
   if not st.pointCount or st.version~=st.path.version then
    st.pointCount=0;for _,segment in pairs(st.path.segments) do st.pointCount=st.pointCount+#segment.points end
   end
   if (rec or nearStart) and st.pointCount+MAX_POINTS<=8192 then Path.record(st.path,lap,gate-1,car.pos) end
   st.localProgress={gate=gate,lap=lap,vehicle=car.id,playerID=p.playerID,cuts=cuts}
   if st.version~=st.path.version then
    st.version=st.path.version
    for name in pairs(st.history) do st.resets[name]='History reset: route estimate updated' end
    st.history={};st.pointCount=nil
   end
  elseif car and car.localDriver and st.path then
   st.path.recording=nil;st.localProgress=nil
  end
 end
 local keep,n={},0
 for _,row in ipairs(s.leaderboard or {}) do
  local p=participants[row.playerName];n=n+1
  if n>MAX_RACERS then break end
  if not st.path then
   st.status[row.playerName]=st.reason or 'Route estimate unavailable'
  elseif not p then
   st.status[row.playerName]='Participant record missing'
  elseif seenPID[tonumber(p.playerID)]~=1 then
   st.status[row.playerName]='Player ID is missing or duplicated'
  else
   keep[p.playerName]=true;append(st,p.playerName,p,cars[tonumber(p.playerID)],now)
  end
 end
 for name in pairs(st.history) do if not keep[name] then st.history[name]=nil end end
 -- Follow BJR's exact leaderboard order (including penalties); never sort by
 -- the local projection. Sitting-out rows aren't in BJRaceHud either.
 local rows={}
 for _,row in ipairs(s.leaderboard or {}) do if not row.sittingOut then rows[#rows+1]=row end end
 local foundView=false
 for i,row in ipairs(rows) do if viewName and row.playerName==viewName then
  foundView=true
  out.position=i
  for _,side in ipairs({'ahead','behind'}) do
   local r=rows[i+(side=='ahead' and -1 or 1)]
   if r then
    local values=side=='ahead' and gap(st,r.playerName,viewName,now) or gap(st,viewName,r.playerName,now)
    -- Official state can mark a car out before its participant update arrives.
    if not running(row) or not running(r) then values={} end
    values.playerName=r.playerName;values.displayName=r.displayName
    out[side]=values
   end
  end
  break
 end end
 if not foundView then out.reason=viewName and 'Local player not found in leaderboard' or 'Local player name unavailable' end
 return out
end
return G
