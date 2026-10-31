-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Local applied tunes, restricted to the same model and fitted hardware.
-- Alternating slots keep the previous committed generation on a failed write.
local L={}
local function copy(v) if type(v)~='table' then return v end;local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t end
local function stable(v)
 if type(v)=='string' then return 'string:'..string.format('%q',v) end
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={'{'};for _,k in ipairs(keys) do out[#out+1]=string.format('%q',tostring(k))..'='..stable(v[k])..';' end
 out[#out+1]='}';return table.concat(out)
end
L.signature=stable
local function name(n) return type(n)=='string' and #n<=80 and n:match('%S') and not n:find('[%c]') end
local function validStore(v)
 if type(v)~='table' or v.schema~=1 or type(v.entries)~='table' or type(v.generation)~='number' or
  v.generation<0 or v.generation%1~=0 or type(v.nextID)~='number' or v.nextID<1 or v.nextID%1~=0 then return false end
 local count=0
 for id,e in pairs(v.entries) do
  count=count+1
  if count>100 or not tostring(id):match('^%d+$') or tonumber(id)>=v.nextID or type(e)~='table' or not name(e.name) or
   type(e.model)~='string' or e.model=='' or type(e.hardware)~='string' or type(e.vars)~='table' or type(e.diffs)~='table' then return false end
  local n=0;for key,x in pairs(e.vars) do n=n+1;if n>1024 or type(key)~='string' or type(x)~='number' or x~=x or math.abs(x)==math.huge then return false end end
 end
 return true
end
function L.new(api)
 local store,slot={schema=1,generation=0,nextID=1,entries={}},'b'
 local damaged=false
 for _,s in ipairs({'a','b'}) do
  local ok,v=pcall(api.read,s)
  if not ok or (v~=nil and not validStore(v)) then damaged=true;v=nil end
  if validStore(v) and v.generation>store.generation then store=v;slot=s end
 end
 local self={}
 local function commit(nextStore)
  if damaged and store.generation==0 then return false,'Setup library is damaged; restore its settings files from backup before saving.' end
  nextStore.generation=store.generation+1
  if not validStore(nextStore) or #stable(nextStore)>2000000 then return false,'Setup library is invalid or exceeds its size limit.' end
  local target=slot=='a' and 'b' or 'a'
  local ok=pcall(api.write,target,nextStore)
  local readOK,verified=pcall(api.read,target)
  if not ok or not readOK or stable(verified)~=stable(nextStore) then return false,'Could not save setup library; previous version retained.' end
  store=nextStore;slot=target;return true,'Setup library saved.'
 end
 function self.get(id) return store.entries[tostring(id)] and copy(store.entries[tostring(id)]) end
 function self.list(model,hardware,vars)
  local rows={}
  for id,e in pairs(store.entries) do if e.model==model then
   local changes=0;for k,v in pairs(e.vars or {}) do if (vars or {})[k]~=v then changes=changes+1 end end
   rows[#rows+1]={id=id,name=e.name,model=e.model,pi=e.pi,class=e.class,created=e.created,compatible=e.hardware==hardware,changes=changes}
  end end
  table.sort(rows,function(a,b) return a.name:lower()<b.name:lower() end);return rows
 end
 local function unique(n,model,except)
  for id,e in pairs(store.entries) do if id~=except and e.model==model and e.name:lower()==n:lower() then return false end end;return true
 end
 function self.save(n,entry)
  if not name(n) then return false,'Enter a setup name (1–80 characters).' end
  if not unique(n,entry.model) then return false,'A setup with that name already exists; choose a new version name.' end
  local count=0;for _ in pairs(store.entries) do count=count+1 end
  if count>=100 then return false,'Library is full (100 setups); delete an old version first.' end
  local nextStore=copy(store);local id=tostring(nextStore.nextID);nextStore.nextID=nextStore.nextID+1
  local e=copy(entry);e.name=n;e.created=api.now();nextStore.entries[id]=e
  return commit(nextStore)
 end
 function self.change(action,id,n)
  id=tostring(id);local e=store.entries[id];if not e then return false,'Setup no longer exists.' end
  if action=='duplicate' then return self.save(n,e) end
  if action~='rename' and action~='delete' then return false,'Unknown library action.' end
  if action=='rename' and (not name(n) or not unique(n,e.model,id)) then return false,'Use a unique setup name (1–80 characters).' end
  local nextStore=copy(store)
  if action=='delete' then nextStore.entries[id]=nil else nextStore.entries[id].name=n end
  return commit(nextStore)
 end
 return self
end
return L
