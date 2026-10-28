-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Observations are session/racer-key scoped. A position change is not proof of a pass.
local A={}
local function key(r) return r and r.racerKey and tostring(r.racerKey) end
local function positive(n) return type(n)=='number' and n==n and n>0 and n<math.huge end
function A.new()
 local runs,capabilities={},{};local self={}
 function self.capabilities(info)
  capabilities={};for _,event in ipairs(type(info)=='table' and info.events or {}) do capabilities[event]=true end
 end
 function self.reset() runs={} end
 function self.clear(id) runs[tostring(id)]=nil end
 function self.event(name,d)
  if type(d)~='table' or d.sessionId==nil then return end
  local id=tostring(d.sessionId)
  if name=='RaceCountdown' then
   local s={phase=d.phaseIndex,rows={}};runs[id]=s
   for i,r in ipairs(d.grid or {}) do local k=key(r);if k then s.rows[k]={start=r.gridPosition or i,worst=r.gridPosition or i,resets=0} end end
  elseif name=='RaceGreenLight' then
   local s=runs[id]
   if not s or s.phase~=d.phaseIndex then s={phase=d.phaseIndex,rows={}};runs[id]=s end
   s.green=(d.greenAt and d.greenAt.unixMs) or (d.at and d.at.unixMs);s.complete=true
   for _,r in ipairs(d.racers or {}) do local k=key(r);if k and not s.rows[k] then s.rows[k]={resets=0} end end
  else
   local s=runs[id];if not s or not s.complete or s.phase~=d.phaseIndex then return end
   if name=='RacePositionsChanged' then
    for _,c in ipairs(d.changes or {}) do local row=s.rows[key(c.racer)];if row and positive(c.to) then row.worst=math.max(row.worst or c.to,c.to) end end
   elseif name=='RacerReset' then local row=s.rows[key(d.racer)];if row then row.resets=row.resets+1 end
   elseif name=='RaceControl' then local row=s.rows[key(d.racer)];if row then row.penaltyMs=d.penaltyMs;row.stewarded=true end end
  end
 end
 function self.result(res)
  local s=runs[tostring(res.runID)];local awards={};res.awards=awards
  -- BJR sends countdown, green light, position and reset events for every
 -- phase; each countdown starts a new record, so a weekend's awards come from
 -- its last phase, the race. Practice and qualifying never count.
  local function pick(id,label,metric,largest)
   local best,winners=nil,{}
   for _,r in ipairs(res.rows or {}) do
    if not r.disqualified and r.status~='DSQ' then
     local value,detail=metric(r,s and s.rows[key(r)])
     if value and (best==nil or (largest and value>best) or (not largest and value<best)) then best=value;winners={} end
     if value and value==best then winners[#winners+1]={name=r.name,playerID=r.playerID,racerKey=r.racerKey,value=value,detail=detail} end
    end
   end
   if #winners>0 then awards[#awards+1]={id=id,label=label,winners=winners} end
  end
  pick('fastest','Fastest valid lap',function(r) if r.best and not r.best.invalid and positive(r.best.time) then return r.best.time end end)
  pick('gained','Most places gained',function(r,o)
   if s and s.complete and o and r.status=='FIN' and positive(r.position) and o.start and o.start>r.position then return o.start-r.position end
  end,true)
  pick('comeback','Comeback of the race',function(r,o)
   if capabilities.RacePositionsChanged and s and s.complete and o and r.status=='FIN' and positive(r.position) and o.start and o.worst and o.worst>=o.start+2 and o.worst-r.position>=2 then return o.worst-r.position end
  end,true)
  pick('clean','Cleanest driver',function(r,o)
   local inc=r.incidents;local finish=tonumber(r.total);local elapsed=finish and math.max(0,finish-(tonumber(r.bjrPenaltyMs) or 0))
   if not s or not s.complete or not o or not inc or r.status~='FIN' or not elapsed or elapsed<5000 or not s.green then return end
   if not capabilities.RacerReset or not capabilities.RaceControl or not res.recordContext or (res.recordContext.rules or {}).trackLimits=='off' then return end
   local coverage=math.max(0,math.min(inc.lastAt or 0,s.green/1000+elapsed/1000)-math.max(inc.firstAt or 0,s.green/1000))
   if coverage<elapsed/1000*.8 or (inc.samples or 0)<3 or (inc.maxGap or 0)>10 then return end
   if (r.cuts or 0)>0 or (inc.contacts or 0)>0 or r.falseStart or o.resets>0 or (r.bjrPenaltyMs or 0)>0 or o.stewarded then return end
   return 0,'No recorded cuts, fault contacts, resets or penalties; telemetry covered the run.'
  end)
  res.awardsNote='Ties share awards. Comeback requires losing at least two places after the grid. Cleanest requires recorded telemetry coverage; unknown is not clean.'..((res.phaseCount or 1)>1 and ' Weekend awards are for the race only.' or '')
 end
 return self
end
return A
