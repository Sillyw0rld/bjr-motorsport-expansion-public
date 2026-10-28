-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- A frozen current-map pick per UTC week; never invent a target or switch maps.
local W={}
function W.new(api)
 local loaded=api.read();local broken=loaded==nil and api.exists()
 local store=loaded or {schema=1,picks={}}
 if type(store)~='table' or store.schema~=1 or type(store.picks)~='table' then broken=true end
 local self={}
 function self.get(level)
  if broken then return nil,'Weekly data is damaged; restore the server backup.' end
  local now=api.now();local week=math.floor((now+259200)/604800);local id=tostring(week)..':'..tostring(level)
  local pick=store.picks[id]
  if pick==nil then
   local options={}
   for _,g in pairs(api.groups()) do
    if api.available(g) then
     local rows={};for _,r in pairs(g.bests or {}) do if r.verified==true and not (api.blocked and api.blocked(r.driver,r.runID)) and api.carAvailable(r.model) then rows[#rows+1]=r end end
     table.sort(rows,function(a,b) if a.time~=b.time then return a.time<b.time end;return tostring(a.driver)..':'..a.model<tostring(b.driver)..':'..b.model end)
     if #rows>0 then options[#options+1]={group=g,target=rows[math.ceil(#rows/2)]} end
    end
   end
   table.sort(options,function(a,b) return a.group.id<b.group.id end)
   if #options==0 then return nil,'Record a server-verified Rivals lap on an available layout and car to seed this week’s challenge.' end
   local chosen=options[week%#options+1];local g=chosen.group
   pick={id=id,week=week,starts=week*604800-259200,ends=(week+1)*604800-259200,published=now,level=level,
    challenge=g.id,raceID=g.raceID,raceName=g.raceName,class=g.class,layout=g.layout,rulesKey=g.rulesKey,rules=api.copy(g.rules),target=api.copy(chosen.target)}
   local nextStore={schema=1,picks={}}
   for k,p in pairs(store.picks) do if type(p)=='table' and type(p.week)=='number' and p.week>=week-8 then nextStore.picks[k]=p end end
   nextStore.picks[id]=pick
   if not api.write(nextStore) then return nil,'Could not persist a weekly target; previous data retained.' end
   store=nextStore
  end
  if type(pick)~='table' or pick.id~=id or pick.week~=week or pick.level~=level or pick.ends~=(week+1)*604800-259200 or
   type(pick.class)~='string' or type(pick.layout)~='string' or type(pick.rulesKey)~='string' or type(pick.rules)~='table' or
   type(pick.target)~='table' or type(pick.target.driver)~='string' or type(pick.target.model)~='string' or type(pick.target.time)~='number' or
   not (pick.target.time>=5000 and pick.target.time<=1800000) then return nil,'Weekly target is invalid; restore its backup.' end
  if pick.target.verified~=true or (api.blocked and api.blocked(pick.target.driver,pick.target.runID)) then return pick,'This week’s preserved target is unverified or moderated. It is unavailable; record a server-verified lap for a future week.' end
  if not api.available(pick) or not api.carAvailable(pick.target.model) then return pick,'This week’s layout, rules or car is unavailable. The target has been preserved.' end
  return pick
 end
 function self.view(level,driver)
  local p,why=self.get(level)
  if not p then return {available=false,message=why} end
  local target={};for k,v in pairs(p.target) do if k~='sourcePath' and k~='driver' then target[k]=v end end
  target.competitor=p.target.driver
  return {id=p.id,available=why==nil,message=why,challenge=p.challenge,raceID=p.raceID,raceName=p.raceName,class=p.class,
   starts=p.starts,ends=p.ends,published=p.published,target=target,personal=driver==p.target.driver}
 end
 return self
end
return W
