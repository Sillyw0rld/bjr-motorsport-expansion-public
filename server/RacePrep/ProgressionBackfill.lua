-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local Rivals=dofile(path..'/Rivals.lua');local R=dofile(path..'/ProgressionRewards.lua');local L=dofile(path..'/Licences.lua')
local B={}
function B.run(s,input,hash,settings,blocked)
 if s.backfill and s.backfill.done then return false end
 local names,report={}, {driversRead=0,resultsRead=0,trustedResults=0,unmatchedRows=0,done=true}
 local counts={};local jobs={}
 for raw,p in pairs(input.profiles.drivers or {}) do
  p=R.profile(p)
  local id=hash(raw);report.driversRead=report.driversRead+1
  if names[p.name]~=nil then names[p.name]=false else names[p.name]=id end
  local d=R.init(s.drivers[id] or {});s.drivers[id]=d;d.name=p.name;d.profile=p
  d.skill=input.score((input.skills.players or {})[raw]);L.update(d,p,d.skill,settings.licences,false)
 end
 for _,res in ipairs(input.results) do
  report.resultsRead=report.resultsRead+1
  if R.raceAllowed(res) then
   report.trustedResults=report.trustedResults+1;local rows={}
   for _,row in ipairs(res.rows or {}) do
    local id=row.rivalDriver or names[row.name or row.playerName]
    if id then
     local d=R.init(s.drivers[id] or {name=row.name,profile={},skill=1000});s.drivers[id]=d
     rows[#rows+1]={id=id,name=d.name,profile=d.profile or {},skill=d.skill,row=row}
     if row.status=='FIN' and not row.disqualified then counts[id]=(counts[id] or 0)+1 end
    else report.unmatchedRows=report.unmatchedRows+1 end
   end
   jobs[#jobs+1]={result=res,rows=rows}
  end
 end
 -- Lifetime finish XP uses the explicitly allowed profile aggregates. Bonuses
 -- and streaks require trusted results; missing history never invents them.
 for id,d in pairs(s.drivers) do d.xp=100*math.max(0,((d.profile or {}).finished or 0)-(counts[id] or 0)) end
 for _,job in ipairs(jobs) do R.race(s,job) end
 local groups={}
 for _,res in ipairs(input.results) do for _,row in ipairs(res.rows or {}) do
  if row.rivalDriver and R.verified(res,row,blocked) and res.recordContext then
   local c=res.recordContext;local key=Rivals.key(c,row.class)
   local g=groups[key] or {bests={},raceName=res.raceName,class=row.class,type=c.type};groups[key]=g
   local old=g.bests[row.rivalDriver]
   if not old or row.best.time<old.time then g.bests[row.rivalDriver]={driver=row.rivalDriver,name=row.name,time=row.best.time,metric=row.best.metric,model=row.model,runID=res.runID,verified=true} end
  end
 end end
 for _,res in ipairs(input.results) do
  local w=input.weeklies and input.weeklies[res.weeklyID];local p=input.challenges and input.challenges[res.rotationID]
  if p then p.available=true;w={rotations={p}} end
  R.rival(s,res,nil,w,blocked)
 end
 R.boards(s,groups,blocked)
 for _,d in pairs(s.drivers) do R.finish(d) end
 s.backfill=report;return true
end
return B
