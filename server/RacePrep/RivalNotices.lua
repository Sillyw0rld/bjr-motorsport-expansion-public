-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Salted inboxes; every publication is checked, invalid storage stays untouched.
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local Rewards=dofile(path..'/ProgressionRewards.lua');local Rivals=dofile(path..'/Rivals.lua')
local N={}
local function valid(s)
 if type(s)~='table' or s.schema~=1 or type(s.serial)~='number' or s.serial<0 or s.serial~=s.serial or s.serial==math.huge or type(s.inboxes)~='table' or type(s.runs)~='table' then return false end
 for run,v in pairs(s.runs) do if type(run)~='string' or v~=true then return false end end
 for id,rows in pairs(s.inboxes) do
  if type(id)~='string' or type(rows)~='table' or #rows>20 then return false end
  for _,n in ipairs(rows) do
   if type(n)~='table' then return false end
   for _,key in ipairs({'id','driver','runID','board','level','raceName','class','name'}) do if type(n[key])~='string' then return false end end
   if type(n.gap)~='number' or n.gap<=0 or n.gap~=n.gap or n.gap==math.huge or type(n.serial)~='number' or type(n.seen)~='boolean' then return false end
  end
 end
 return true
end
function N.bests(group,blocked)
 local out={}
 for _,r in pairs(group and group.bests or {}) do if r.verified and not blocked(r.driver,r.runID) then
  local old=out[r.driver]
  if not old or r.time<old.time or r.time==old.time and tostring(r.runID)<tostring(old.runID) then out[r.driver]=r end
 end end
 return out
end
local function holder(bests)
 local best
 for _,r in pairs(bests) do if not best or r.time<best.time or r.time==best.time and r.driver<best.driver then best=r end end
 return best
end
function N.new(api)
 local state=api.read();local broken=state==nil and api.exists()
 if state==nil then state={schema=1,serial=0,inboxes={},runs={}} end
 if not valid(state) then broken=true end
 local staged;local pendingPosts={};local self={}
 if broken then api.log('Rival inbox damaged; restore its backup before writing.');state={schema=1,serial=0,inboxes={},runs={}} end
 local function save(nextState)
  staged=nextState
  if not api.write(nextState) then api.log('Rival inbox write failed; retained in memory for retry. Restore storage before restarting.');return false end
  state=nextState;staged=nil;return true
 end
 function self.retry()
  if broken then return false end
  if staged and not save(staged) then return false end
  for _,p in ipairs(pendingPosts) do if api.record and not api.blocked(p.driver,p.runID) then api.record(p) end end;pendingPosts={};return true
 end
 function self.broken() return broken end
 function self.prune()
  if broken then return false end
  local s=api.copy(staged or state);local changed=false
  for _,rows in pairs(s.inboxes) do for i=#rows,1,-1 do local n=rows[i];if api.blocked(n.driver,n.runID) then table.remove(rows,i);changed=true end end end
  if changed then return save(s) end
  return self.retry()
 end
 function self.record(res,previous)
  if broken or type(res.recordContext)~='table' then return false end
  local s=api.copy(staged or state);local run=tostring(res.runID or '')
  if run=='' or s.runs[run] then return false end
  local row=res.rows and res.rows[1]
  if not row or not row.rivalDriver or not Rewards.verified(res,row,api.blocked) then return false end
  local c=res.recordContext;local key=Rivals.key(c,tostring(row.class))
  local before=N.bests(previous,api.blocked);local old=before[row.rivalDriver]
  if old and row.best.time>=old.time then return false end
  local prior=holder(before)
  for id,y in pairs(before) do if id~=row.rivalDriver and row.best.time<y.time and (not old or y.time<old.time) then
   s.serial=s.serial+1;local rows=s.inboxes[id] or {};s.inboxes[id]=rows
   table.insert(rows,1,{id=run..':'..s.serial,serial=s.serial,driver=row.rivalDriver,runID=run,board=key,level=res.level,
    raceName=res.raceName or 'Rivals',class=row.class,name=row.name or 'Driver',gap=row.best.metric and y.metric and math.abs(y.metric.value-row.best.metric.value)or y.time-row.best.time,metricType=c.type,unit=row.best.metric and row.best.metric.unit,seen=false})
   while #rows>20 do table.remove(rows) end
  end end
  s.runs[run]=true
  -- Keep a bounded history of processed run IDs. The inbox retains its source
  -- independently, so moderation can remove every remaining affected notice.
  local count=0;for _ in pairs(s.runs) do count=count+1 end
  if count>2000 then s.runs={};for _,rows in pairs(s.inboxes) do for _,n in ipairs(rows) do s.runs[n.runID]=true end end;s.runs[run]=true end
  local changedHolder=prior and prior.driver~=row.rivalDriver and row.best.time<prior.time
  if changedHolder and api.recordsEnabled() then
   pendingPosts[#pendingPosts+1]={driver=row.rivalDriver,runID=run,raceName=res.raceName,class=row.class,name=row.name,time=row.best.lapTime or row.best.time}
  end
  if not save(s) then return false end
  self.retry();return true
 end
 function self.view(id)
  local out={}
  for _,n in ipairs(state.inboxes[id] or {}) do if not api.blocked(n.driver,n.runID) then
   local v=api.copy(n);v.text=string.format('%s beat your time at %s · %s by %.2f s',n.name,n.raceName,n.class,n.gap/1000)
   if n.metricType and n.metricType~='bestLap' then local value=n.unit=='m/s' and n.gap*3.6 or n.unit=='ms' and n.gap/1000 or n.gap;local unit=n.unit=='m/s' and 'km/h' or n.unit=='ms' and 's' or 'laps';v.text=string.format('%s moved ahead at %s · %s by %.2f %s',n.name,n.raceName,n.class,value,unit)end
   local best=N.bests(api.groups(n.level)[n.board],api.blocked)[n.driver]
   if not best then v.enabled=false;v.reason='This lap is no longer available'
   elseif best.ghost==false then v.enabled=false;v.reason='Ghosts are available for lap-based challenges only'
   elseif api.level()~=n.level then v.enabled=false;v.reason='Join '..n.level..' to race this ghost'
   else v.enabled=true;v.reason='Race their ghost';v.target={challenge=n.board,runID=best.runID,competitor=best.driver,model=best.model} end
   out[#out+1]=v
  end end
  return out
 end
 function self.deliver(id,kind)
  if broken or not self.retry() then return false end
  local rows={};local s=api.copy(state)
  for _,n in ipairs(s.inboxes[id] or {}) do if not n.seen and not api.blocked(n.driver,n.runID) and (kind~='join' or #rows<5) then rows[#rows+1]=n.id;n.seen=true end end
  if #rows==0 then return true end
  if not save(s) then return false end
  local wanted={};for _,n in ipairs(rows) do wanted[n]=true end
  local payload={kind=kind,items={}}
  for _,v in ipairs(self.view(id)) do if wanted[v.id] then payload.items[#payload.items+1]=v end end
  api.send(id,payload);return true
 end
 function self.target(id,notice)
  for _,v in ipairs(self.view(id)) do if v.id==notice then return v.enabled and v.target or nil,v.reason end end
  return nil,'This lap is no longer available'
 end
 return self
end
return N
