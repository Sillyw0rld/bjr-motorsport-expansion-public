-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BeamJoy-Revived's state for BJR:ME's server, from BJR's own plugin API and
-- its saved race files (BJR:ME adds nothing to BJR's folders since 2.14.2):
--   runs     races.sessions, polled every second (RacePrep.lua): phase, racers,
--            laps, countdown remaining and race time per BJR race session
--   level    server.info at start and the MapChanged event
--   races    the current map's race layouts, read from
--            BeamJoyData/db/activities/<map>_races.json (gates, start
--            positions, sectors), reloaded on BJR's RacesChanged event
--   players  players.online (every 10 s): staff flag and display names
local H={enabled=false,at=0,permissions={},races={},runs={},cuts={},gridRatings={},spectators={}}
function H.fresh() return H.enabled and os.time()-H.at<5 end

-- y/x angle in every quadrant (BeamMP's Lua 5.3 has math.atan(y,x); kept explicit)
local function atan2(y,x)
 if x>0 then return math.atan(y/x) end
 if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
 if y>0 then return math.pi/2 end
 if y<0 then return -math.pi/2 end
 return 0
end
--- one BJR race (as saved) -> the layout BJR:ME's sessions and timing use
function H.normalize(r)
 local groups,steps={},{}
 for i,g in ipairs(r.gates or {}) do
  local n=g.step or i;groups[n]=groups[n] or {}
  groups[n][#groups[n]+1]={pos=g.pos,dir=g.dir,radius=(g.width or 10)/2,height=g.height or 10}
 end
 local keys={};for n in pairs(groups) do keys[#keys+1]=n end;table.sort(keys)
 for _,n in ipairs(keys) do steps[#steps+1]=groups[n] end
 if r.loopable and #steps>1 then local first=table.remove(steps,1);steps[#steps+1]=first end
 local starts={}
 for _,p in ipairs(r.startPositions or {}) do
  local d=p.dir or {x=0,y=-1,z=0};local yaw=atan2(d.x,-d.y)/2
  starts[#starts+1]={pos=p.pos,dir=p.dir,rot=p.rot or {x=0,y=0,z=math.sin(yaw),w=math.cos(yaw)}}
 end
 return {id=r.id,name=r.name,steps=steps,startPositions=starts,loopable=r.loopable,branchingEnabled=r.branchingEnabled,nativeRace={gates=r.gates,loopable=r.loopable,branchingEnabled=r.branchingEnabled,manualSectors=r.manualSectors,sectorCount=r.sectorCount}}
end
--- the map's saved races (BJR's activities file, a list) -> layouts
function H.setRaces(level,list)
 H.racesLevel=level;H.races={}
 for _,r in ipairs(type(list)=='table' and list or {}) do if type(r)=='table' and r.id~=nil then H.races[#H.races+1]=H.normalize(r) end end
end
function H.setLevel(level)
 if level~=H.level then H.races={};H.racesLevel=nil end
 H.level=level
end
--- races.sessions -> runs (keyed by session ID). nowMs: unix ms
local PHASE={GRID='grid',COUNTDOWN='race',RACE='race',FINISHED='finished'}
function H.fromSessions(sessions,nowMs)
 local runs={}
 for _,s in ipairs(type(sessions)=='table' and sessions or {}) do
  if type(s)=='table' and s.sessionId~=nil then
   local id=tostring(s.sessionId);local ids,laps={},{}
   for _,r in ipairs(s.racers or {}) do if r.id then ids[#ids+1]=tonumber(r.id);laps[tostring(r.id)]=tonumber(r.lap) end end
   local green=type(s.greenAt)=='table' and tonumber(s.greenAt.unixMs) or nil
   runs[id]={runID=id,raceID=s.raceId,raceName=s.raceName,phase=PHASE[s.state] or 'grid',level=s.map or H.level,participants=ids,laps=laps,
    remaining=s.state=='COUNTDOWN' and green and math.max(0,green-nowMs) or 0,
    elapsed=s.state=='RACE' and green and math.max(0,(nowMs-green)/1000) or 0}
  end
 end
 return runs
end
--- a fresh races.sessions answer
function H.setRuns(runs)
 H.runs=runs;H.at=os.time()
 for id in pairs(H.cuts) do if not H.runs[id] then H.cuts[id]=nil end end
 for id in pairs(H.gridRatings) do if not H.runs[id] then H.gridRatings[id]=nil end end
end
--- players.online -> staff flags and display names
function H.setPlayers(players)
 local permissions,names={},{}
 for _,p in ipairs(type(players)=='table' and players or {}) do
  if p.id then permissions[tostring(p.id)]=p.staff==true;names[tostring(p.id)]=p.displayName or p.name end
 end
 H.permissions,H.names=permissions,names
end
function H.canEdit(pid) return H.fresh() and H.permissions[tostring(pid)]==true end
function H.runFor(pid)
 if not H.fresh() then return end
 for _,s in pairs(H.runs) do for _,id in ipairs(s.participants or {}) do if tonumber(id)==tonumber(pid) then return s.runID end end end
 return H.spectators[tostring(pid)]
end
function H.targets(runID)
 local out={};if not H.fresh() then return out end
 for pid in pairs(MP.GetPlayers()) do if H.runFor(pid)==runID then out[#out+1]=tonumber(pid) end end
 return out
end
function H.race(level,id)
 if not H.fresh() or level~=H.level then return end
 if H.racesLevel~=H.level and H.loadRaces then H.setRaces(H.level,H.loadRaces(H.level)) end
 for _,r in pairs(H.races) do if tostring(r.id)==tostring(id) then return r end end
end
function H.cut(pid,p)
 local id=H.runFor(pid);local s=id and H.runs[id]
 if not s or s.phase~='race' or tostring(s.raceID)~=tostring(p.raceID) then return false end
 local lap=tonumber(p.lap);local current=(s.laps or {})[tostring(pid)]
 if not lap or lap%1~=0 or (not current or math.abs(lap-current)>1) then return false end
 H.cuts[id]=H.cuts[id] or {};local cuts=H.cuts[id]
 cuts[tostring(pid)]=cuts[tostring(pid)] or {};local laps=cuts[tostring(pid)]
 laps[tostring(lap)]=(laps[tostring(lap)] or 0)+1;return true
end
function H.results(res,rules)
 local cuts=H.cuts[res.runID] or {};local fastest
 for _,row in ipairs(res.rows or {}) do
  row.cuts=0;row.best=nil;row.bestAny=nil;row.bestSectors={};row.fastestLap=nil;row.theoretical=nil
  local byLap=cuts[tostring(row.playerID)] or {}
  for _,lap in ipairs(row.lapList or {}) do
   lap.cuts=byLap[tostring(lap.lap)] or 0;lap.invalid=rules.trackLimits~='off' and lap.cuts>0
   row.cuts=row.cuts+lap.cuts
   if not row.bestAny or lap.time<row.bestAny.time then row.bestAny=lap end
   if not lap.invalid then
    if not row.best or lap.time<row.best.time then row.best={time=lap.time,lap=lap.lap,sectors=lap.sectors} end
    for i,t in pairs(lap.sectors or {}) do if not row.bestSectors[i] or t<row.bestSectors[i] then row.bestSectors[i]=t end end
   end
  end
  local expected=tonumber(res.sectorCount) or 0
  for _,lap in ipairs(row.lapList or {}) do expected=math.max(expected,#(lap.sectors or {})) end
  local complete,total=expected>0,0
  for i=1,expected do if row.bestSectors[i] then total=total+row.bestSectors[i] else complete=false end end
  if complete then row.theoretical=total end
  if rules.trackLimits=='penalty' then
   row.penalty=math.max(0,row.cuts-rules.cutPenaltyAfter)*rules.cutPenaltySeconds*1000
   if row.total then row.total=row.total+row.penalty end
  end
  if row.best and (not fastest or row.best.time<fastest.best.time) then fastest=row end
 end
 local completed=0;for _,row in ipairs(res.rows or {}) do completed=math.max(completed,row.laps or 0) end
 for _,row in ipairs(res.rows or {}) do if (row.laps or 0)<completed then row.lapsDown=completed-(row.laps or 0) end end
 if fastest then fastest.fastestLap=true end
 return res
end
return H
