-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local T={}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
function T.new(api)
 local loaded=api.read()
 local broken=(loaded==nil and api.exists and api.exists()) or false
 local store=loaded or {schema=1,nextID=1,entries={}}
 if type(store)~='table' or store.schema~=1 or type(store.entries)~='table' or type(store.nextID)~='number' or store.nextID%1~=0 or store.nextID<1 then broken=true end
 if not broken then for _,e in pairs(store.entries) do
  if type(e)~='table' or type(e.name)~='string' or type(e.model)~='string' or type(e.owner)~='string' or type(e.hardware)~='string' or type(e.vars)~='table' or type(e.diffs)~='table' then broken=true;break end
 end end
 local last={};local self={}
 local function reply(pid,p) api.send(pid,'RacePrepSharedTunes',p) end
 function self.disconnect(pid) last[pid]=nil end
 function self.handle(pid,p)
  local now=api.now();local budget=last[pid]
  if not budget or now-budget.at>=10 then budget={at=now,n=0};last[pid]=budget end
  budget.n=budget.n+1;if budget.n>20 then return end
  if type(p)~='table' then return end
  if broken then reply(pid,{error='The shared tune file is damaged; ask the server owner to restore its backup.'});return end
  local owner=api.identity(pid);if not owner then return end
  if p.action=='list' then
   local items={}
   for id,e in pairs(store.entries) do if e.model==p.model then items[#items+1]={id=id,name=e.name,author=e.author,originalAuthor=e.originalAuthor,
    class=e.class,pi=e.pi,updated=e.updated,compatible=e.hardware==p.hardware,owned=e.owner==owner,notes=e.notes} end end
   table.sort(items,function(a,b) return a.name:lower()<b.name:lower() end)
   reply(pid,{items=items,model=p.model});return
  end
  local e=store.entries[tostring(p.id)]
  if p.action=='download' then
   if not e then reply(pid,{error='Shared tune no longer exists.'});return end
   local entry=api.copy(e);entry.owner=nil;entry.id=tostring(p.id)
   reply(pid,{entry=entry});return
  end
  local nextStore=api.copy(store)
  if p.action=='delete' then
   if not e or e.owner~=owner then reply(pid,{error='Only the author may remove this tune.'});return end
   nextStore.entries[tostring(p.id)]=nil
  elseif p.action=='publish' then
   local v=p.entry;local car=api.car(pid,p.vehicle)
   if type(v)~='table' or not car or car.model~=v.model or type(v.name)~='string' or #v.name<1 or #v.name>80 or v.name:find('%c') or
    type(v.hardware)~='string' or #v.hardware>100000 or type(v.vars)~='table' or type(v.diffs)~='table' then reply(pid,{error='Choose a compatible applied build and a valid named tune.'});return end
   local n=0
   for key,value in pairs(v.vars) do n=n+1;if n>1024 or type(key)~='string' or #key>160 or not finite(value) then reply(pid,{error='Invalid tuning values.'});return end end
   n=0
   for name,d in pairs(v.diffs) do
    n=n+1;if n>16 or type(name)~='string' or #name>100 or type(d)~='table' then reply(pid,{error='Invalid differential data.'});return end
    for key,value in pairs(d) do
     if key=='mode' then if not ({stock=true,open=true,lsd=true,locked=true})[value] then reply(pid,{error='Invalid differential mode.'});return end
     elseif not ({split=true,frontShare=true,preload=true,lock=true,coast=true})[key] or not finite(value) then reply(pid,{error='Invalid differential setting.'});return end
    end
   end
   local total,mine,id=0,0,nil
   for key,tune in pairs(store.entries) do total=total+1;if tune.owner==owner then mine=mine+1;if tune.model==v.model and tune.name:lower()==v.name:lower() then id=key end end end
   if not id and (total>=200 or mine>=20) then reply(pid,{error='Shared library limit reached (20 per author, 200 per server).'});return end
   id=id or tostring(nextStore.nextID);if not store.entries[id] then nextStore.nextID=nextStore.nextID+1 end
   local original=v.sharedSource and store.entries[tostring(v.sharedSource)]
   nextStore.entries[id]={name=v.name,model=v.model,hardware=v.hardware,vars=api.copy(v.vars),diffs=api.copy(v.diffs),owner=owner,
    author=api.name(pid),originalAuthor=original and (original.originalAuthor or original.author),class=car.class,pi=car.pi,updated=now,
    notes=type(p.notes)=='string' and p.notes:gsub('%c',' '):sub(1,240) or ''}
  else return end
  if not api.write(nextStore) then reply(pid,{error='Could not save shared tunes; previous library retained.'});return end
  store=nextStore;reply(pid,{message='Shared tune library saved. Refresh the list to see changes.'})
 end
 return self
end
return T
