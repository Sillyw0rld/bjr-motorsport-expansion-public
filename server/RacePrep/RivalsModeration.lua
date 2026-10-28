-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Tombstones preserve original history; blocked drivers stay off all boards.
local M={}
function M.new(api)
 local store=api.read();local broken=store==nil and api.exists()
 store=store or {schema=1,blocked={},removed={},audit={}}
 if type(store)~='table' or store.schema~=1 or type(store.blocked)~='table' or type(store.removed)~='table' or type(store.audit)~='table' then broken=true end
 local requests={};local self={}
 function self.blocked(driver,run)
  return broken or (driver~=nil and store.blocked[driver]==true) or (run~=nil and store.removed[run]==true)
 end
 function self.list()
  local rows={};if broken then return rows end
  for driver in pairs(store.blocked) do
   local name
   for i=#store.audit,1,-1 do if store.audit[i].driver==driver and store.audit[i].name then name=store.audit[i].name;break end end
   rows[#rows+1]={driver=driver,name=name}
  end
  table.sort(rows,function(a,b) return a.driver<b.driver end);return rows
 end
 function self.handle(pid,p)
  if not api.allowed(pid) or broken or type(p)~='table' then return false end
  local now=api.now();if requests[pid] and now-requests[pid]<2 then return false end;requests[pid]=now
  if p.action~='remove' and p.action~='block' and p.action~='unblock' then return false end
  if type(p.driver)~='string' or #p.driver>128 then return false end
  if p.action=='remove' and (type(p.runID)~='string' or #p.runID>256) then return false end
  -- An arbitrary client-supplied identifier is not sufficient for moderation.
  if not api.known(p.driver,p.runID,p.action) then return false end
  if #store.audit>=10000 then return false end -- fail closed until owner archives audit
  local nextStore=api.copy(store)
  if p.action=='remove' then nextStore.removed[p.runID]=true else nextStore.blocked[p.driver]=p.action=='block' or nil end
  local entry={at=now,by=api.actor(pid),action=p.action,driver=p.driver,name=api.name and api.name(p.driver),runID=p.action=='remove' and p.runID or nil}
  nextStore.audit[#nextStore.audit+1]=entry
  if not api.write(nextStore) then return false end
  store=nextStore;api.log('Rivals moderation '..p.action..' by '..tostring(entry.by)..' driver='..p.driver..' run='..tostring(entry.runID))
  api.changed();return true
 end
 function self.disconnect(pid) requests[pid]=nil end
 return self
end
return M
