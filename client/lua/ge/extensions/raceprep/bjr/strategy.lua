-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Fuel use measured between completed laps; no guessed economy/tyre lifespan.
local M={}
local state,baseline,context={samples=0,tanks={}}
function M.reset() state={samples=0,tanks={}};baseline=nil;context=nil end
function M.sample(rows,key,lap,remaining,now)
 if not key or key~=context then M.reset();context=key end
 state.at=now;state.tanks={};state.remaining=remaining
 local energy={}
 local liquid=false;for _,r in ipairs(rows or {}) do if r.storageType=='fuelTank' then liquid=true end end
 for _,r in ipairs(rows or {}) do
  if type(r.energy)=='number' and type(r.maxEnergy)=='number' and r.maxEnergy>0 and r.energy>=0 then
   if (liquid and r.storageType=='fuelTank') or (not liquid and r.storageType=='electricBattery') or r.storageType==nil then energy[r.name]={energy=r.energy,capacity=r.maxEnergy} end
   state.tanks[#state.tanks+1]={name=r.name,energyType=r.energyType,percent=r.energy/r.maxEnergy*100,volume=r.volume,capacity=r.capacity,storageType=r.storageType}
  end
 end
 if not lap then baseline=nil;state.lapsRemaining=nil;state.recommendedPercent=nil;return end
 if not baseline then baseline={lap=lap,energy=energy};return end
 local refilled=false
 for name,r in pairs(energy) do
  local old=baseline.energy[name]
  if not old or old.capacity~=r.capacity or r.energy>old.energy+math.max(1,r.capacity*.002) then refilled=true end
 end
 if refilled or lap<baseline.lap then M.reset();context=key;baseline={lap=lap,energy=energy};return end
 if lap>baseline.lap then
  local used={};local count=lap-baseline.lap
  for name,r in pairs(energy) do local old=baseline.energy[name];if old then used[name]=math.max(0,(old.energy-r.energy)/count) end end
  state.average=state.average or {}
  for name,use in pairs(used) do state.average[name]=((state.average[name] or 0)*state.samples+use)/(state.samples+1) end
  state.samples=math.min(100,state.samples+1);baseline={lap=lap,energy=energy}
 end
 local laps,recommended
 for name,r in pairs(energy) do
  local avg=state.average and state.average[name]
  if avg and avg>r.capacity*.0001 then
   laps=math.min(laps or math.huge,r.energy/avg)
   if remaining then recommended=math.max(recommended or 0,avg*(remaining+1)/r.capacity*100) end
  end
 end
 state.lapsRemaining=laps;state.recommendedPercent=recommended;state.insufficient=remaining and laps and laps<remaining+1 or false
end
function M.view() return state end
return M
