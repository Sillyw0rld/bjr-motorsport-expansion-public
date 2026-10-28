-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Journal complete snapshots before publishing crew/season changes and awards.
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local C=dofile(path..'/Crews.lua');local S=dofile(path..'/Seasons.lua');local R=dofile(path..'/ProgressionRewards.lua')
local L={}
function L.new(api)
 local crews=api.read('crews.json');local seasons=api.read('seasons.json');local pending=api.read('league-pending.json')
 local broken=(crews==nil and api.exists('crews.json')) or (seasons==nil and api.exists('seasons.json')) or (pending==nil and api.exists('league-pending.json'))
 if crews==nil then crews=C.new() end;if seasons==nil then seasons=S.new() end
 if not C.valid(crews) or not S.valid(seasons) then broken=true end
 if pending~=nil and (type(pending)~='table' or pending.schema~=1) then broken=true end
 if broken then crews=C.new();seasons=S.new() end
 local self={}
 function self.broken() return broken end
 function self.retry()
  if broken then return false end
  if not pending then return true end
  if type(pending)~='table' or pending.schema~=1 or not C.valid(pending.crews) or not S.valid(pending.seasons) or type(pending.awards)~='table' then broken=true;return false end
  for id,list in pairs(pending.awards) do if type(id)~='string' or type(list)~='table' then broken=true;return false end end
  if not api.write('crews.json',pending.crews) or not api.write('seasons.json',pending.seasons) or not api.grant(pending.awards) then return false end
  if not api.write('league-pending.json',{schema=1,empty=true}) then return false end
  crews,seasons=pending.crews,pending.seasons;pending=nil;return true
 end
 if type(pending)=='table' and pending.schema==1 and pending.empty==true then pending=nil end
 local function transaction(fn)
  if not self.retry() then return false,'League data unavailable; restore its backup or server storage.' end
  local c,s,awards=api.copy(crews),api.copy(seasons),{}
  local ok,changed,why=pcall(fn,c,s,awards)
  if not ok then api.log('League operation failed safely: '..tostring(changed));return false,'League operation could not be completed.' end
  if changed==false then return false,why elseif changed=='noop' then return true end
  local job={schema=1,crews=c,seasons=s,awards=awards}
  if not api.write('league-pending.json',job) then return false,'Could not journal league changes; previous state retained.' end
  pending=job;return self.retry()
 end
 function self.tick(at)
  return transaction(function(c,s,awards)
   local now=at or api.now();local changed=false
   if not at and api.canClose and not api.canClose() then return 'noop' end
   if not s.current then local ok,why=S.start(s,api.settings().seasons,now);if not ok then return false,why end;changed=true end
   local steps=0
   while s.current.status=='active' and s.current.ends and now>=s.current.ends do
    steps=steps+1;if steps>1200 then return false,'Too many expired seasons; ask staff to inspect data.' end
    local old=s.current;S.close(s,c,old.ends,awards);changed=true
    local settings=api.settings().seasons or old.settings
    if settings.repeating~=false then
     local duration=(settings.mode=='custom' and old.settings.mode=='custom' and settings.customEnd==old.settings.customEnd) and old.duration or nil
     local ok,why=S.start(s,settings,old.ends,true,duration);if not ok then return false,why end
    end
   end
   return changed and true or 'noop'
  end)
 end
 function self.action(actor,p,staff)
  if type(p)~='table' or type(p.action)~='string' then return false end
  if p.area=='season' then
   if not staff then return false,'Motorsport rules permission required.' end
   return transaction(function(c,s,awards)
    local current=s.current
    if p.action=='start' then if current and current.status=='active' then return false,'End the current season first.' end;return S.start(s,api.settings().seasons,api.now(),true) end
    if not current or current.status~='active' then return false,'No active season.' end
    if p.action=='rename' and type(p.name)=='string' and #p.name>0 and #p.name<=80 and not p.name:find('[%c]') then current.name=p.name;return true end
    if p.action=='extend' then local ends=S.date(p.date);if not ends or ends<=api.now() or current.ends and ends<=current.ends then return false,'Choose a later end date.' end;current.ends=ends;return true end
    if p.action=='end' then
     S.close(s,c,api.now(),awards)
     local cfg=api.settings().seasons or current.settings
     if cfg.repeating~=false then return S.start(s,cfg,api.now(),true,cfg.mode=='custom' and current.settings.mode=='custom' and cfg.customEnd==current.settings.customEnd and current.duration or nil) end
     return true
    end
    return false,'Unknown season action.'
   end)
  end
  return transaction(function(c) return C.apply(c,actor,p,(api.settings().crews or {}).maxMembers or 4,api.now(),staff,api.known) end)
 end
 local function clean(res,row)
  for _,a in ipairs(res.awards or {}) do if a.id=='clean' then for _,w in ipairs(a.winners or {}) do if row.racerKey and row.racerKey==w.racerKey or row.playerID~=nil and row.playerID==w.playerID then return true end end end end
  return false
 end
 function self.score(job)
  if not self.tick(job.result.completedAt or api.now()) then return false end
  return transaction(function(c,s)
   if job.kind=='medals' then
    local changed=false
    for _,a in ipairs(job.medalAwards or {}) do changed=S.bonus(s,a.id,a.name,'medal',a.board,a.tier,a.class,a.time,job.result.completedAt,job.crewSnapshot or c) or changed end
    return changed and true or 'noop'
   end
   if job.kind~='rival' then
    if not R.raceAllowed(job.result) then return 'noop' end
    return S.race(s,job.result,job.rows,job.crewSnapshot or c,clean) and true or 'noop'
   end
   local res=job.result;local changed=false;local context=res.recordContext
   if not context then return 'noop' end
   for _,row in ipairs(res.rows or {}) do if row.rivalDriver and R.verified(res,row,api.blocked) then
    for _,pick in ipairs(job.weekly and job.weekly.rotations or {})do
     if pick.kind=='weekly' and R.challengeMet(res,row,pick,api.blocked)then changed=S.bonus(s,row.rivalDriver,row.name,'weekly',pick.id,1,row.class,row.best.time,res.completedAt,job.crewSnapshot or c)or changed end
    end
    local w=job.weekly
    if w and w.target and w.target.verified and res.weeklyID==w.id and row.best.time<w.target.time and not api.blocked(w.target.driver,w.target.runID) then
     changed=S.bonus(s,row.rivalDriver,row.name,'weekly',w.id,1,row.class,row.best.time,res.completedAt,job.crewSnapshot or c) or changed
    end
   end end
   return changed and true or 'noop'
  end)
 end
 function self.view(actor,page,includeHistory)
  if broken then return {error='Crew/season data is damaged; staff must restore its backup.'} end
  local current=seasons.current
  local pages=math.max(1,math.ceil(#seasons.history/20));page=math.max(1,math.min(pages,math.floor(tonumber(page) or 1)))
  local history,hall={},{}
  if includeHistory~=false then for i=math.max(1,#seasons.history-page*20+1),#seasons.history-(page-1)*20 do history[#history+1]=seasons.history[i];hall[#hall+1]=seasons.hallOfFame[i] end end
  return {crews=C.view(crews,actor,api.drivers()),current=current and {id=current.id,name=current.name,starts=current.starts,ends=current.ends,status=current.status,settings=current.settings,tables=S.tables(current,crews)},
   history=includeHistory~=false and history or nil,hallOfFame=includeHistory~=false and hall or nil,page=includeHistory~=false and page or nil,pages=pages,pending=pending~=nil}
 end
 function self.snapshot(ids)
  local out={members={},crews={}}
  for _,id in ipairs(ids) do
   local cid=crews.members[id];local c=cid and crews.crews[cid]
   if c then out.members[id]=cid;out.crews[cid]={id=cid,name=c.name,tag=c.tag,colour=c.colour} end
  end
  return out
 end
 function self.crew(id) local c=crews.members[id] and crews.crews[crews.members[id]];return c and {id=c.id,name=c.name,tag=c.tag,colour=c.colour} end
 self.retry();self.tick()
 return self
end
return L
