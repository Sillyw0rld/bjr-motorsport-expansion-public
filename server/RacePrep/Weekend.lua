-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR:ME's BeamJoy-Revived event format. BJR owns every clock, lap and phase;
-- this module only builds the public phase payload and the stable client view.
local W={}
W.FORMAT_ID='weekend'
W.FORMAT_REF='RacePrep:'..W.FORMAT_ID
W.STAGES={practice='Practice',qualifying='Qualifying',grid='Grid',race='Race',break_='Break',ended='Ended'}

local function whole(v,default,lo,hi)
 v=tonumber(v);if not v or v~=v then v=default end
 return math.floor(math.max(lo,math.min(hi,v)))
end

function W.phases(o)
 o=o or {};local out={}
 local practice=whole(o.practiceMinutes,10,0,120)
 local qualifying=whole(o.qualifyingMinutes,10,0,120)
 local laps=whole(o.raceLaps,5,1,1000)
 if practice>0 then out[#out+1]={name='Practice',timeLimitMin=practice,afterTime='own',ranking='best',countsToEvent=false,leaderboard=false,breakS=15} end
 if qualifying>0 then out[#out+1]={name='Qualifying',timeLimitMin=qualifying,afterTime='own',ranking='best',countsToEvent=false,leaderboard=false,breakS=20} end
 out[#out+1]={name='Race',laps=laps,ranking='position',countsToEvent=true,leaderboard=true}
 return out
end

function W.format(o)
 return {id=W.FORMAT_ID,name='BJR:ME weekend',description='Practice, qualifying and one counted race. Motorsport Expansion supplies the grid and race rules.',
  result='last',track='any',locked={'phases','name','ranking','countsToEvent','leaderboard'},phases=W.phases(o)}
end

function W.openPayload(o)
 local phases=W.phases(o)
 return {raceId=tonumber(o.raceID) or o.raceID,name=o.name or 'BJR:ME weekend',holdStart=o.holdStart==true,
  -- The registered format is for BJR's start menu. The Motorsport tab sends
  -- its actual phase list directly so zero-minute phases can truly be omitted.
  options={phases=phases,result='last'}}
end

function W.isRacePhase(x)
 local p=type(x)=='table' and (x.phase or (x.session and x.session.phase)) or nil
 if type(p)=='table' then return p.name=='Race' or (p.ranking=='position' and p.countsToEvent~=false) end
 local s=type(x)=='table' and x.session or nil
 return not (s and tonumber(s.phaseCount) and tonumber(s.phaseCount)>1)
end

function W.new(o,now)
 local phases=W.phases(o)
 return {raceID=tostring(o.raceID),level=o.level,raceName=o.raceName,practiceMinutes=whole(o.practiceMinutes,10,0,120),
  qualifyingMinutes=whole(o.qualifyingMinutes,10,0,120),raceLaps=whole(o.raceLaps,5,1,1000),gridOrder=o.gridOrder,
  by=o.by,startedAt=now,stage='grid',phaseIndex=0,phaseCount=#phases,sessionId=nil,phases=phases,results={}}
end

function W.update(w,d,state)
 if not w or not d or tostring(d.raceId or d.raceID)~=w.raceID then return false end
 if w.sessionId and d.sessionId and tostring(w.sessionId)~=tostring(d.sessionId) then return false end
 w.sessionId=d.sessionId or w.sessionId;w.phaseIndex=d.phaseIndex or w.phaseIndex;w.phaseCount=d.phaseCount or w.phaseCount
 local name=d.phase and d.phase.name
 if state=='finished' then w.stage='ended'
 elseif state=='break' then w.stage='break_'
 elseif state=='grid' then w.stage='grid'
 elseif name then w.stage=name:lower()
 elseif state then w.stage=state end
 return true
end

-- A weekend opened from BJR's format menu has no Motorsport-tab request.
function W.fromSession(d,now)
 if type(d)~='table' or d.format~=W.FORMAT_REF or not d.sessionId then return nil end
 local options={raceID=d.raceId,level=d.map,raceName=d.raceName,practiceMinutes=0,qualifyingMinutes=0,raceLaps=d.laps or 5}
 for _,p in ipairs(d.phases or {}) do
  if p.name=='Practice' then options.practiceMinutes=p.timeLimitMin or 0
  elseif p.name=='Qualifying' then options.qualifyingMinutes=p.timeLimitMin or 0
  elseif p.name=='Race' then options.raceLaps=p.laps or 5 end
 end
 local w=W.new(options,now);w.sessionId=d.sessionId
 W.update(w,d,'grid');return w
end

function W.phaseView(d,nowMs)
 local p=d.phase or {};local kind=tostring(p.name or ''):lower()
 if kind~='practice' and kind~='qualifying' then return nil end
 local ended=d.results~=nil;local rows={}
 for _,r in ipairs(d.results or d.racers or {}) do
  local bestSectors,lapList={},{}
  for _,lap in ipairs(r.laps or {}) do
   lapList[#lapList+1]={lap=lap.lap,time=lap.timeMs,sectors=lap.sectorsMs}
   if lap.timeMs==r.bestLapMs then bestSectors=lap.sectorsMs or {} end
  end
  rows[#rows+1]={playerID=r.id,racerKey=r.racerKey,name=r.name,model=r.vehicle,best=r.bestLapMs,
   laps=ended and #lapList or math.max(0,(tonumber(r.lap) or 1)-1),bestSectors=bestSectors,lapList=lapList}
 end
 table.sort(rows,function(a,b)
  if a.best~=b.best then return (a.best or math.huge)<(b.best or math.huge) end
  return tostring(a.racerKey or a.playerID)<tostring(b.racerKey or b.playerID)
 end)
 for i,r in ipairs(rows) do r.pos=i;r.gap=r.best and rows[1].best and r.best-rows[1].best or nil end
 local remaining=d.endsAt and tonumber(d.endsAt.unixMs)
 return {id=tostring(d.sessionId)..'-'..tostring(d.phaseIndex),native=true,level=d.map,raceID=tostring(d.raceId),raceName=d.raceName,
  type=kind,label=p.name,state=ended and 'ended' or (d.timeUpAt and 'overtime' or 'running'),minutes=p.timeLimitMin,
  remaining=remaining and math.max(0,remaining-(nowMs or 0)) or 0,rows=rows}
end

function W.view(w)
 if not w then return nil end
 return {raceID=w.raceID,level=w.level,raceName=w.raceName,stage=w.stage,label=W.STAGES[w.stage] or w.stage,
  practiceMinutes=w.practiceMinutes,qualifyingMinutes=w.qualifyingMinutes,raceLaps=w.raceLaps,gridOrder=w.gridOrder,by=w.by,
  sessionId=w.sessionId,phaseIndex=w.phaseIndex,phaseCount=w.phaseCount,phases=w.phases,grid=w.grid,results=w.results,mode=w.mode}
end

function W.first(w) if w.practiceMinutes>0 then return 'practice',w.practiceMinutes elseif w.qualifyingMinutes>0 then return 'qualifying',w.qualifyingMinutes end return 'grid' end
function W.after(w,k) if k=='practice' and w.qualifyingMinutes>0 then return 'qualifying',w.qualifyingMinutes end return 'grid' end
function W.raceStarted(w,id) if w and tostring(id)==w.raceID then w.stage='race';return true end return false end
function W.raceFinished(w,id) if w and tostring(id)==w.raceID then w.stage='ended';return true end return false end
function W.gridList(order) local out={} for i,e in ipairs(order or {}) do out[i]={pos=i,playerID=e.playerID,racerKey=e.racerKey,name=e.name} end return out end
return W
