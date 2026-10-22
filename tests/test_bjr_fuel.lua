-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local rows,command
serialize=function(t) rows=t;return '{}' end
obj={getID=function() return 7 end,queueGameEngineLua=function(_,s) command=s end}
local tanks={main={energyType='gasoline',storedEnergy=200,energyCapacity=1000},battery={energyType='electricEnergy',storedEnergy=500,energyCapacity=2000},air={energyType='air',storedEnergy=10,energyCapacity=100}}
energyStorage={getStorages=function() return tanks end,getStorage=function(n) return tanks[n] end}
local f=dofile('client/lua/vehicle/extensions/raceprepFuel.lua');f.snapshot('token')
assert(#rows==2 and command:find('onFuel(7,"token"',1,true))
f.apply{main=300,battery=99999,air=0};assert(tanks.main.storedEnergy==300 and tanks.battery.storedEnergy==2000 and tanks.air.storedEnergy==10)
f.apply{main=0/0};assert(tanks.main.storedEnergy==300)
f.applyPercent{main=25,air=50,battery=150};assert(tanks.main.storedEnergy==250 and tanks.air.storedEnergy==10 and tanks.battery.storedEnergy==2000)
print('PASS: native tank snapshot, per-tank restore, battery capacity, air exclusion and invalid value refusal')
-- A new fuel's lower energy per litre must not refill or drain the tank.
f.apply{main={energy=200,capacity=2000}}
assert(tanks.main.storedEnergy==100,'cross-fuel restoration preserves fill fraction')
f.apply{main={energy=200,capacity=0}}
assert(tanks.main.storedEnergy==100,'invalid conversion snapshot ignored')
