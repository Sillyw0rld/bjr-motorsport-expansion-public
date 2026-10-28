-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BeamMP v3.9.4 adapter. Fail closed when a required API is absent.
local B={}
function B.new(mp,decode,canonical,verification)
 local cache={};local self={}
 local function vid(pid,sid)
  if type(sid)~='string' then return end
  local p,v=sid:match('^(%d+)%-(%d+)$')
  if tonumber(p)==tonumber(pid) then return tonumber(v) end
 end
 function self.clock() return mp.GetServerTimeMS() end
 function self.available() return type(mp.GetServerTimeMS)=='function' and type(mp.GetPositionRaw)=='function' and type(mp.GetPlayerVehicles)=='function' end
 function self.position(pid,sid)
  local id=vid(pid,sid);if not id then return nil,'Wrong vehicle owner' end
  return mp.GetPositionRaw(tonumber(pid),id)
 end
 function self.config(pid,sid,car)
  local id=vid(pid,sid);if not id then return nil,'Wrong vehicle owner.' end
  local cars=mp.GetPlayerVehicles(tonumber(pid));local raw=type(cars)=='table' and (cars[id] or cars[tostring(id)])
  local old=cache[sid]
  if old and old.raw==raw and old.key==car.key then return old.signature end
  local signature,why=verification.config(raw,decode,canonical,car.parts,car.model)
  if signature then cache[sid]={raw=raw,key=car.key,signature=signature} end
  return signature,why
 end
 function self.disconnect(pid)
  for sid in pairs(cache) do if sid:match('^(%d+)%-')==tostring(pid) then cache[sid]=nil end end
 end
 return self
end
return B
