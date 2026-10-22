-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local W=dofile('client/lua/vehicle/extensions/raceprepWeight.lua')
local tank={type='fuelTank',fuelNodeMassCoef=.01,storedEnergy=1000,remainingVolume=53,energyCapacity=2000,
    fuelNodes={[1]=85}}
local masses={}
tank.updateGFX=function(self)
    for id,base in pairs(self.fuelNodes) do masses[id]=base+self.storedEnergy*self.fuelNodeMassCoef end
end
energyStorage={getStorages=function() return {tank=tank,battery={type='electricBattery',storedEnergy=2000}} end}
v={data={raceprepBody={scale=.85}}}
assert(W.apply())
assert(math.abs(masses[1]-(100+10)*.85)<1e-9,'dry + fuel uniformly scaled')
assert(tank.storedEnergy==1000 and tank.remainingVolume==53 and tank.energyCapacity==2000,'no fuel/energy changes')
assert(W.apply() and math.abs(tank.fuelNodeMassCoef-.0085)<1e-12,'no compounding')
assert(W.apply(.85000002384186) and math.abs(tank.fuelNodeMassCoef-.0085)<1e-12,'JBeam float32 round trip')
tank.storedEnergy=500
assert(W.apply() and math.abs(masses[1]-(100+5)*.85)<1e-9,'fuel consumption still scales correctly')
assert(W.apply(1) and tank.fuelNodeMassCoef==.01,'coefficient reversible')
assert(not W.apply(.5) and tank.fuelNodeMassCoef==.01,'unknown scale fails closed')
print('PASS: native body fuel-node mass scaling, reset reapply, reversibility and unchanged fuel energy')
