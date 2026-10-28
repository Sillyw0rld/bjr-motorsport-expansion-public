-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Bounded background jobs. Ratings enter through the normal validated report.
local A={}
local function config(v) if type(v)~='string'then return end;local name=v:gsub('\\','/'):match('([^/]+)$');return name and name:gsub('%.pc$','')end
A.config=config
function A.rated(entries,car,key)
 local cfg=config(car.config);local e=key and entries[key]
 return cfg~=nil and type(e)=='table'and e.model==car.model and config(e.config)==cfg and type(e.pi)=='number'and e.pi>=100 or false
end
-- A synced worker car appears in every player's world: never while anyone
-- races or runs Rivals.
function A.busy(clients)
 for _,c in ipairs(clients or {})do if not c.free or c.rivals then return true end end
 return false
end
function A.choose(clients,localOnly)
 if not localOnly and A.busy(clients)then return end
 local eligible={};for _,c in ipairs(clients or {})do if c.ready and c.free and not c.rivals and c.idle>=30 and (localOnly or c.staff)then eligible[#eligible+1]=c end end
 table.sort(eligible,function(a,b)if a.staff~=b.staff then return a.staff end;return tonumber(a.pid)<tonumber(b.pid)end)
 return eligible[1]
end
function A.new(api)
 local disk=api.read();local broken=disk==nil and api.exists();disk=disk or {schema=1,cars={}}
 if type(disk)~='table'or disk.schema~=1 or type(disk.cars)~='table'then broken=true end
 if not broken then for model,r in pairs(disk.cars)do if type(model)~='string'or type(r)~='table'or type(r.day)~='number'or type(r.attempts)~='number'or r.attempts<0 or r.attempts>3 then broken=true;break end end end
 local self={};local job;local function day()return math.floor(api.now()/86400)end
 local function row(car)local r=disk.cars[car.model];return r and r.day==day()and r or {day=day(),attempts=0,key=r and r.key,config=r and r.config}end
 local function rated(car)if broken then return false end;local r=row(car);return api.rated(car,r.config==config(car.config)and r.key or nil)end
 local function finish(reason)
  if not job then return end
  api.send(job.pid,{action='stop',id=job.id,reason=reason})
  local s=api.copy(disk);s.cars[job.model]=s.cars[job.model]or{day=day(),attempts=1};s.cars[job.model].reason=reason
  if api.write(s)then disk=s else broken=true end
  job=nil
 end
 function self.view()
  local out={items={},rated=0,total=0,localOnly=api.localOnly==true,error=broken and 'Rating queue damaged or not writable; restore rating-jobs.json.'or nil}
  for _,car in ipairs(api.cars())do
   out.total=out.total+1;local known=rated(car);local r=not broken and row(car)or{}
   local status=known and'rated'or job and job.model==car.model and'rating'or(r.attempts or 0)>=3 and'failed'or'pending'
   if known then out.rated=out.rated+1 end
   out.items[#out.items+1]={model=car.model,name=car.name,config=car.config,status=status,attempts=r.attempts or 0,reason=r.reason}
  end
  out.running=job and{model=job.model,pid=job.pid};return out
 end
 function self.tick()
  if broken then return end
  if job then
   local clients=api.clients();local c;for _,v in ipairs(clients)do if tonumber(v.pid)==tonumber(job.pid)then c=v end end
   if rated(job)then finish('Rated');return end
   if not c or not c.ready or not c.free or c.rivals or c.idle<30 then finish('Stopped: player became active, joined a race or left.');return end
   if not api.localOnly and A.busy(clients)then finish('Stopped: a race or Rivals run started.');return end
   if api.now()-job.at>30 then finish('Could not rate: timed out waiting for the normal rating report.');return end
   return
  end
  local candidate=A.choose(api.clients(),api.localOnly);if not candidate then return end
  local view=self.view()
  for _,car in ipairs(api.cars())do
   if not rated(car)and row(car).attempts<3 then
    local s=api.copy(disk);local r=api.copy(row(car));r.attempts=r.attempts+1;r.reason='Rating in progress';s.cars[car.model]=r
    if not api.write(s)then broken=true;return end;disk=s
    job={id=api.token(),pid=candidate.pid,model=car.model,config=car.config,at=api.now()}
    api.send(candidate.pid,{action='start',id=job.id,model=car.model,config=car.config,index=view.rated+1,total=view.total,localOnly=api.localOnly==true})
    return
   end
  end
 end
 function self.defaultKey(car)local r=not broken and row(car);return r and r.config==config(car.config)and r.key or nil end
 function self.accept(pid,report,key)
  if not job or tonumber(pid)~=tonumber(job.pid)or report.model~=job.model or config(report.config)~=config(job.config)then return false end
  local s=api.copy(disk);local r=s.cars[job.model];r.key=key;r.config=config(job.config)
  if not api.write(s)then broken=true;return false end;disk=s;return true
 end
 function self.message(pid,p)
  if not job or tonumber(pid)~=tonumber(job.pid)or p.id~=job.id then return false end
  if p.action=='failed'or p.action=='abort'then finish(type(p.reason)=='string'and p.reason:sub(1,200)or'Could not rate');return true end
  -- A client's "done" is not proof: wait for normal server-validated storage.
  if p.action=='done'and rated(job)then finish('Rated');return true end
  return false
 end
 function self.disconnect(pid)if job and tonumber(pid)==tonumber(job.pid)then finish('Stopped: player left.')end end
 return self
end
return A
