-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Read-only engine classification. No upgrades or physics changes here.
local M={}
local function nonempty(v) return type(v)=='string' and v~='' and v or nil end
local function fuelFor(device,jd,storages)
 local fuel=nonempty(jd.requiredEnergyType) or nonempty(device.requiredEnergyType)
 if fuel then return fuel:lower() end
 local names=jd.energyStorage or device.energyStorage
 if type(names)=='string' then names={names} end
 local found
 for _,name in pairs(type(names)=='table' and names or {}) do
  local storage=storages and storages[name]
  local f=storage and nonempty(storage.energyType)
  if f then
   f=f:lower()
   if found and found~=f then return nil end
   found=f
  end
 end
 return found
end
function M.detect(devices,data,storages)
 local out={kind='unknown',supported=false,engines={},forcedInduction=false}
 local ice,electric,automation,unknown=0,0,0,0
 for _,device in pairs(devices or {}) do
  local jd=(data or {})[device.name] or {}
  local kind='unknown'
  local fuel=fuelFor(device,jd,storages)
  if device.type=='camsoEngine' then kind='automation';automation=automation+1
  elseif device.type=='electricMotor' then kind='electric';electric=electric+1
  elseif device.type=='combustionEngine' then
   kind=fuel=='gasoline' and 'petrol' or fuel=='diesel' and 'diesel' or 'unknown'
   if kind~='unknown' then ice=ice+1 end
  end
  if kind=='unknown' then unknown=unknown+1 end
  local turbo=type(device.turbocharger)=='table' and device.turbocharger.isExisting==true or
   type(jd.turbocharger)=='string' and type((data or {})[jd.turbocharger])=='table'
  local supercharger=type(device.supercharger)=='table' and device.supercharger.isExisting==true or
   type(jd.supercharger)=='string' and type((data or {})[jd.supercharger])=='table'
  turbo,supercharger=turbo==true,supercharger==true
  out.forcedInduction=out.forcedInduction or turbo or supercharger
  out.engines[#out.engines+1]={name=device.name,type=device.type,kind=kind,fuel=fuel,
   turbo=turbo,supercharger=supercharger}
 end
 table.sort(out.engines,function(a,b) return tostring(a.name)<tostring(b.name) end)
 if #out.engines==0 or unknown>0 then return out end
 if automation>0 then
  if ice>0 or electric>0 then return out end
  out.kind='automation'
 elseif ice>0 and electric>0 then out.kind='hybrid'
 elseif electric>0 then out.kind='electric'
 elseif ice>0 then
  out.kind=out.engines[1].kind
  for _,e in ipairs(out.engines) do if e.kind~=out.kind then out.kind='unknown';return out end end
 end
 out.supported=out.kind~='unknown'
 return out
end
return M
