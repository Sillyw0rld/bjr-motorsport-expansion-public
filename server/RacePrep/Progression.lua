-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Private salted identities only. Queue first, then apply idempotently.
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local L=dofile(path..'/Licences.lua')
local R=dofile(path..'/ProgressionRewards.lua')
local Backfill=dofile(path..'/ProgressionBackfill.lua')
local M={}
function M.new(api)
 local state=api.read('progression.json');local broken=state==nil and api.exists('progression.json')
 if state==nil then state={schema=1,drivers={},seen={}} end
 if type(state)~='table' or state.schema~=1 or type(state.drivers)~='table' or type(state.seen)~='table' then broken=true end
 local jobs=api.read('progression-pending.json');if jobs==nil and api.exists('progression-pending.json') then broken=true end
 jobs=jobs or {};if type(jobs)~='table' then broken=true;jobs={} end
  if not broken then
  for id,d in pairs(state.drivers) do if type(id)~='string' or type(d)~='table' or (d.licence~=nil and L.rank(d.licence)==0) then broken=true;break end
   for _,field in ipairs({'achievements','medals','weekly','challengeXP','earnedLicences','profile','podiumClasses'}) do if d[field]~=nil and type(d[field])~='table' then broken=true end end
   if d.xp~=nil and (type(d.xp)~='number' or d.xp~=d.xp or d.xp<0 or d.xp==math.huge) then broken=true end end
 end
 if broken then state={schema=1,drivers={},seen={}} end
 local self={}
 function self.data() return state end
 function self.broken() return broken end
 function self.pending() return next(jobs)~=nil end
 function self.suspend() broken=true end
 function self.change(fn)
  if broken then return false end
  local nextState=api.copy(state);local ok,result=pcall(fn,nextState)
  if not ok then broken=true;api.log('Progression operation stopped safely: '..tostring(result));return false end
  if result==false then return false end
  if not api.write('progression.json',nextState) then return false end
  state=nextState;return true
 end
 function self.flush()
  if broken then return false end
  local keys={};for k in pairs(jobs) do keys[#keys+1]=k end;table.sort(keys,function(a,b) local x,y=jobs[a],jobs[b];local ta=type(x)=='table' and type(x.result)=='table' and x.result.completedAt or 0;local tb=type(y)=='table' and type(y.result)=='table' and y.result.completedAt or 0;if ta~=tb then return ta<tb end;if tonumber(a) and tonumber(b) then return tonumber(a)<tonumber(b) end;return a<b end)
  for _,k in ipairs(keys) do
   local job=jobs[k]
   if api.deferEvents and type(job)=='table' and job.crewSnapshot==nil then job.crewSnapshot={members={},crews={}} end
   if type(job)~='table' or type(job.rows)~='table' then broken=true;return false end
   for _,r in ipairs(job.rows) do if type(r)~='table' or type(r.id)~='string' or type(r.profile)~='table' or type(r.skill)~='number' then broken=true;return false end end
   if state.seen[k] then
    if api.event and not api.event(job) then break end
    jobs[k]=nil
   else
   local before={};for id,d in pairs(state.drivers) do before[id]=R.capture(d) end
   for _,r in ipairs(job.rows) do before[r.id]=before[r.id] or R.capture(nil) end
   local receipts
   if self.change(function(s)
    if job.kind=='medals' then R.boards(s,job.groups,function() return false end) elseif job.kind=='rival' then R.rival(s,job.result,job.best,job.weekly,api.blocked) else
    for _,r in ipairs(job.rows) do
     local d=s.drivers[r.id] or {};s.drivers[r.id]=d;d.name=r.name;d.profile=r.profile;d.skill=r.skill
     L.update(d,r.profile,r.skill,api.settings().licences,job.safety==true)
    end
    local _,earned=R.race(s,job,before);receipts=earned
    end
    s.seen[k]=true
   end) then
    -- The seen marker and XP are durable before this ephemeral delivery. A
    -- retried job (including a process restart) cannot replay a reward card.
    if api.reward then
     if receipts then for id,receipt in pairs(receipts) do api.reward(id,receipt) end
     elseif job.kind=='rival' or job.kind=='medals' then
      for id,d in pairs(state.drivers) do
       local old=before[id] or R.capture(nil);local receipt=R.receipt(state,id,old)
       if receipt.total>0 or #receipt.achievements>0 then receipt.kind='notice';receipt.source=job.kind;if job.weekly and job.weekly.rotations then receipt.text='Challenge rewards' end;api.reward(id,receipt) end
      end
      if job.kind=='medals' then for _,a in ipairs(job.medalAwards or {}) do api.reward(a.id,{kind='notice',medal=a.tier,raceName=(job.groups[a.board] or {}).raceName,text='Medal confirmed: '..({'Bronze','Silver','Gold'})[a.tier]}) end end
     end
    end
    if api.event and not api.event(job) then break end
    jobs[k]=nil else break end
   end
  end
  return api.write('progression-pending.json',jobs)
 end
 function self.record(res,rows,safety,snapshot)
  if broken or not R.raceAllowed(res) then return false end
  local k=tostring(res.runID or res.key);if state.seen[k] then return true end
  rows=api.copy(rows);for _,r in ipairs(rows) do r.profile=R.profile(r.profile or {}) end
  jobs[k]={crewSnapshot=snapshot or (api.snapshot and api.snapshot(rows,res)),rows=rows,safety=safety==true,result=api.copy(res),pole=api.pole and api.pole(res.runID),startPole=api.startPole and api.startPole(res.runID)}
  if not api.write('progression-pending.json',jobs) then api.log('Progression queue is in memory only; restore storage before restarting.') end
  if api.deferEvents then return true end
  return self.flush()
 end
 function self.refresh(id,name,p,skill)
  if broken or not id then return end
  p=R.profile(p or {})
  local d=api.copy(state.drivers[id] or {});d.name=name;d.profile=p or {};d.skill=skill
  L.update(d,p,skill,api.settings().licences,false);R.finish(d)
  local old=state.drivers[id]
  if not old or old.licence~=d.licence or old.name~=name or old.skill~=skill or not old.profile or old.profile.races~=(p and p.races) or old.profile.safety~=(p and p.safety) then self.change(function(s) s.drivers[id]=d end) end
 end
 function self.stats(id) local d=self.driver(id);return R.profile(d and d.profile or {}) end
 function self.directory()
  local out={};for id,d in pairs(state.drivers) do if #out>=512 then break end;out[#out+1]={id=id,name=d.name} end
  table.sort(out,function(a,b) return tostring(a.name)<tostring(b.name) end);return out
 end
 function self.driver(id) return not broken and state.drivers[id] or nil end
 function self.view(id) local d=self.driver(id);local v=L.view(d,d and d.profile,d and d.skill);v.name=d and d.name;v.id=id;v.error=broken and 'Progression unavailable; staff must restore its backup.' or nil
  v.xp=d and d.xp or 0;v.level=R.level(v.xp);v.levelStart=R.threshold(v.level);v.nextLevel=R.threshold(v.level+1)
  v.title=R.title(d);v.titleID=d and d.title;v.achievements=R.achievements(state,d);v.medals=d and d.medals or {};v.medalList={}
  for _,m in pairs(v.medals) do v.medalList[#v.medalList+1]=m end
  table.sort(v.medalList,function(a,b) if a.tier~=b.tier then return a.tier>b.tier end;return tostring(a.raceName or a.model)<tostring(b.raceName or b.model) end);return v end
 function self.refusal(minimum,id)
  if minimum and minimum~='' and broken then return 'Licence data unavailable; staff must restore its backup.' end
  return L.refusal(minimum,self.driver(id))
 end
 function self.backfill(input,hash)
  if broken then return false end
  return self.change(function(s) return Backfill.run(s,input,hash,api.settings(),api.blocked) end)
 end
 function self.rival(res,best,weekly)
  if broken then return false end
  local k='rival:'..tostring(res.runID or res.key)
  if state.seen[k] then return true end
  jobs[k]={crewSnapshot=api.snapshot and api.snapshot({},res),kind='rival',rows={},result=api.copy(res),best=best,weekly=api.copy(weekly)}
  api.write('progression-pending.json',jobs);if api.deferEvents then return true end;return self.flush()
 end
 function self.boardMedals(groups)
  local out={};local count=0
  for key,g in pairs(groups or {}) do
   local rows={};out[key]=rows
   for _,r in pairs(g.bests or {}) do
    if r.verified and not api.blocked(r.driver,r.runID) and count<2000 then
     local d=self.driver(r.driver);local m=d and d.medals and d.medals[key]
     if m then rows[r.driver]={tier=m.tier,provisional=m.provisional==true};count=count+1 end
    end
   end
  end
  return out
 end
 function self.medals(groups)
  if broken or self.pending() then return false end
  -- Freeze validated competitors and the entitlement before journalling. Retries
  -- retain confirmation time and crew membership, even across a season boundary.
  local eligible={}
  for key,g in pairs(groups or {}) do
   local v={raceName=g.raceName,class=g.class,bests={}};eligible[key]=v
   for k,r in pairs(g.bests or {}) do if r.verified and not api.blocked(r.driver,r.runID) then v.bests[k]=api.copy(r) end end
  end
  local changed,awards=R.boards(api.copy(state),eligible,function() return false end)
  if not changed then return false end
  local now=api.now and api.now() or os.time();local k='medals:'..tostring(now);while state.seen[k] or jobs[k] do k=k..':' end
  local rows={};for _,a in ipairs(awards) do rows[#rows+1]={rivalDriver=a.id} end
  local res={completedAt=now,rows=rows}
  jobs[k]={kind='medals',rows={},result=res,groups=eligible,medalAwards=awards,crewSnapshot=api.snapshot and api.snapshot({},res)}
  if not api.write('progression-pending.json',jobs) then return false end
  return self.flush()
 end
 -- Only the recipient gets achievement/medal/progress details. Others supply
 -- nameplate data; driver cards and archived league pages are separate actions.
 function self.payload(pid,ids,league,groups)
  local out={self=ids[tostring(pid)],players={},directory=self.directory(),league=league,boardMedals=self.boardMedals(groups)}
  for _,entry in ipairs(out.directory) do for player,id in pairs(ids) do if entry.id==id then entry.playerID=tostring(player) end end end
  for player,id in pairs(ids) do
   local d=self.driver(id);local crew=league and league.crews
   local tag
   for _,c in ipairs(crew and crew.items or {}) do for _,m in ipairs(c.members or {}) do if m.id==id then tag=c.tag end end end
   if tostring(player)==tostring(pid) then out.players[player]=self.view(id);out.players[player].crewTag=tag
   else out.players[player]={letter=L.view(d,d and d.profile,d and d.skill).letter,title=R.title(d),crewTag=tag} end
  end
  return out
 end
 local sent={}
 function self.send(pid,payload,encode,send)
  local wire=encode(payload);if sent[pid]==wire then return false end
  send(pid,'RacePrepProgress',wire);sent[pid]=wire;return true
 end
 function self.disconnect(pid) sent[pid]=nil end
 function self.pick(id,title)
  if type(title)~='string' or #title>64 then return false end
  return self.change(function(s) return s.drivers[id] and R.pick(s.drivers[id],title) or false end)
 end
 if not api.deferEvents then self.flush() end
 return self
end
return M
