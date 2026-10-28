-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Independent of skill Elo. Uses RacePrep's existing salted/account identity.
local S={}
local Rating=dofile(debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):gsub('DriverStats.lua$','DriverRating.lua'))
S.new=function() return {schema=1,drivers={},seen={}} end
local function num(v) v=tonumber(v);return v and v==v and v>=0 and v<math.huge and v or 0 end
S.record=function(store,res,identity,enabled)
 local key=res.runID or res.key
 if not key or store.seen[key] then return false end
 store.seen[key]=true
 local seen={}
 for _,row in ipairs(res.rows or {}) do
  local id=identity(row.playerID,row)
  if id and not seen[id] then
   seen[id]=true
   local d=store.drivers[id] or {name=row.name,races=0,wins=0,podiums=0,finished=0,dnf=0,laps=0,
    cuts=0,contacts=0,falseStarts=0,kilometres=0,safety=3,best={}}
   d.name=row.name or d.name;d.races=d.races+1
   if row.status=='FIN' then d.finished=d.finished+1;if row.position==1 then d.wins=d.wins+1 end
    if num(row.position)>0 and num(row.position)<=3 then d.podiums=d.podiums+1 end
   else d.dnf=d.dnf+1 end
   local incidents=row.incidents or {}
   local cuts,contacts=num(row.cuts),num(incidents.contacts)
   local valid=0;for _,lap in ipairs(row.lapList or {}) do if not lap.invalid and (lap.time==nil or num(lap.time)>0) then valid=valid+1 end end
   d.laps=d.laps+num(row.laps);d.cuts=d.cuts+cuts;d.contacts=d.contacts+contacts
   d.falseStarts=d.falseStarts+(row.falseStart and 1 or 0)
   d.kilometres=d.kilometres+num(incidents.distance)/1000
   if enabled then
    d.safetyRaces=(d.safetyRaces or 0)+1
    local delta=math.min(.25,valid*.025)-cuts*.025-contacts*.10-(row.falseStart and .05 or 0)
    d.safety=math.max(0,math.min(5,(d.safety or 3)+delta))
   end
   local track=tostring(res.level or '')..':'..tostring(res.raceHash or res.raceID or res.raceName)
   if row.status~='DSQ' and not row.disqualified and row.best and not row.best.invalid and num(row.best.time)>0 and (not d.best[track] or row.best.time<d.best[track]) then d.best[track]=row.best.time end
   store.drivers[id]=d
  end
 end
 return true
end
S.view=function(store,identity,players)
 local rows={}
 for pid,name in pairs(players or {}) do
  -- BJR sends its name map through JSON, so IDs arrive as string keys.
  -- BeamMP account lookups require numbers; otherwise the saved driver is
  -- missed and the UI displays the empty provisional profile instead.
  pid=tonumber(pid) or pid
  local id=identity(pid);local d=id and store.drivers[id]
  if d then
   rows[#rows+1]={playerID=tonumber(pid) or pid,name=name,safety=d.safety,safetyGrade=Rating.grade(d.safety),safetyRaces=d.safetyRaces or 0,races=d.races,wins=d.wins,
    podiums=d.podiums,finished=d.finished,dnf=d.dnf,laps=d.laps,cuts=d.cuts,contacts=d.contacts,
    falseStarts=d.falseStarts,kilometres=d.kilometres,provisional=d.races<5}
  else rows[#rows+1]={playerID=tonumber(pid) or pid,name=name,safety=3,safetyGrade="B",safetyRaces=0,races=0,wins=0,laps=0,contacts=0,kilometres=0,provisional=true} end
 end
 table.sort(rows,function(a,b) if a.safety~=b.safety then return a.safety>b.safety end;return tostring(a.name)<tostring(b.name) end)
 return rows
end
return S
