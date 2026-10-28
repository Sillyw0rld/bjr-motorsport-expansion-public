-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Read-only challenges from provenance-bearing ordinary-race results.
local Challenges=dofile(debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):gsub('Rivals.lua$','Challenges.lua'))
local R={}
function R.key(c,class) return c.layout..':'..c.rulesKey..':'..class..(c.type and c.type~='bestLap' and ':'..c.type or '') end
function R.canonical(v)
 if type(v)=='string' then return 'string:'..string.format('%q',v) end
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={'{'};for _,k in ipairs(keys) do out[#out+1]=string.format('%q',tostring(k))..'='..R.canonical(v[k])..';' end
 out[#out+1]='}';return table.concat(out)
end
function R.add(groups,res,sourcePath)
 local c=res.recordContext
 if type(c)~='table' or not c.layout or not c.rulesKey then return end
 for _,row in ipairs(res.rows or {}) do
  local best=row.best
  local verified=res.kind=='rivals' and res.verified==true and type(res.verification)=='table' and res.verification.version==1 and res.verification.method=='beammp-server-crossings' and row.verified==true and best and best.verified==true
  verified=verified==true
  if c.type and c.type~='bestLap' then verified=verified and Challenges.validMetric(best,c.type) end
  if row.rivalDriver and row.buildKey and row.model and row.class and type(row.pi)=='number' and row.pi>0 and row.pi<math.huge and
   not row.disqualified and row.status~='DSQ' and type(best)=='table' and type(best.time)=='number' and best.time>0 and best.time<math.huge and not best.invalid then
   local key=R.key(c,row.class)
   local g=groups[key]
   if not g then
    local count=0;for _ in pairs(groups) do count=count+1 end
    if count<2048 then
     g={id=key,raceID=res.raceID,raceName=res.raceName,layout=c.layout,rulesKey=c.rulesKey,rules=c.rules,class=row.class,type=c.type,options=c.options,preset=c.preset,bests={}};groups[key]=g
    end
   end
   if g then
    -- Retain each driver's best per model so a car filter remains meaningful.
    local driverKey=row.rivalDriver..':'..row.model;local old=g.bests[driverKey]
    local size=0;for _ in pairs(g.bests) do size=size+1 end
    if (old or size<256) and (not old or (verified and not old.verified) or (verified==old.verified and best.time<old.time)) then
     g.bests[driverKey]={driver=row.rivalDriver,name=row.name or row.playerName,model=row.model,car=row.car,pi=row.pi,class=row.class,
      metric=best.metric,lapTime=best.lapTime,ghost=best.ghost,verified=verified==true,sourcePath=sourcePath,time=best.time,lap=best.lap,runID=res.runID or res.key,date=res.date,buildKey=row.buildKey}
    end
   end
  end
 end
end
function R.view(groups,driver,blocked)
 local out={};local count=0
 local keys={};for key in pairs(groups) do keys[#keys+1]=key end;table.sort(keys)
 for _,key in ipairs(keys) do
  local g=groups[key];local rows={}
  for _,r in pairs(g.bests) do if r.verified==true and not (blocked and blocked(r.driver,r.runID)) then rows[#rows+1]=r end end
  table.sort(rows,function(a,b) if a.time~=b.time then return a.time<b.time end;return tostring(a.name)<tostring(b.name) end)
  local view={id=g.id,raceID=g.raceID,raceName=g.raceName,layout=g.layout,rulesKey=g.rulesKey,rules=g.rules,class=g.class,type=g.type,options=g.options,preset=g.preset,rows={}}
  for _,r in ipairs(rows) do
   if count>=2000 then break end
   local v={};for k,x in pairs(r) do if k~='driver' and k~='sourcePath' then v[k]=x end end
   v.competitor=r.driver;v.personal=driver~=nil and r.driver==driver;view.rows[#view.rows+1]=v;count=count+1
  end
  -- Keep empty layouts selectable so the first verified lap can seed a board.
  out[#out+1]=view
 end
 return out,count>=2000
end
return R
