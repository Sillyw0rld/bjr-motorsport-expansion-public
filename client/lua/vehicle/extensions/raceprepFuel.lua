-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- One-shot native energy-storage reads/writes; no reset hooks or file edits.
local M={}
function M.snapshot(token)
 local out={}
 for name,s in pairs(energyStorage.getStorages()) do
  if type(s.energyCapacity)=='number' and s.energyCapacity>0 and s.energyType~='air' then
   out[#out+1]={name=name,energyType=s.energyType,energy=s.storedEnergy,maxEnergy=s.energyCapacity,storageType=s.type,volume=s.type=='fuelTank' and s.remainingVolume or nil,capacity=s.type=='fuelTank' and s.capacity or nil}
  end
 end
 table.sort(out,function(a,b) return a.name<b.name end)
 obj:queueGameEngineLua('if raceprepBJR then raceprepBJR.onFuel('..obj:getID()..','..string.format('%q',token)..','..serialize(out)..') end')
end
function M.apply(values,token)
 for name,value in pairs(values or {}) do
  local s=energyStorage.getStorage(name)
  -- Keep the tank's fill fraction when a conversion changes fuel density.
  -- Numeric callers still supply joules, as before.
  if s and type(value)=='table' then
   local capacity=value.capacity
   value=type(capacity)=='number' and capacity>0 and type(value.energy)=='number' and s.energyCapacity*value.energy/capacity or nil
  end
  if s and s.energyType~='air' and type(value)=='number' and value==value and math.abs(value)<math.huge then
   s.storedEnergy=math.max(0,math.min(s.energyCapacity,value))
  end
 end
 if token then obj:queueGameEngineLua('if raceprepBJR then raceprepBJR.onFuelRestored('..obj:getID()..','..string.format('%q',token)..') end') end
end
-- chosen levels as a percent of each tank (after a reset refilled them)
function M.applyPercent(percents)
 local values={}
 for name,pct in pairs(percents or {}) do
  local s=energyStorage.getStorage(name)
  if s and type(pct)=='number' and pct>=0 and pct<=100 then values[name]=s.energyCapacity*pct/100 end
 end
 M.apply(values)
end
return M
