-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local E=dofile('client/lua/ge/extensions/raceprep/upgradeEffects.lua')
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a)..' ~= '..tostring(b)) end
local engines={{torque={{1000,100},{2000,80}}},{torque={{1000,20},{2000,40}}}}
local p=E.peaks(engines)
near(p.nm,120)
near(p.kw,120*2000*2*math.pi/60/1000)
near(E.powerGain(engines,10).hp,p.hp*.1)
near(E.powerGain(engines,20).lbft,p.lbft*.2)
near(E.powerGain(engines,35).kw,p.kw*.35)
local st={mass=1000,comY=0,engines=engines,wheels={{name='FL',y=-1},{name='FR',y=-1},{name='RL',y=1},{name='RR',y=1}}}
near(E.summary(st).frontShare,.5)
near(E.summary(st).massLB,1000*E.KG_TO_LB)
for kit,share in pairs({street=.08,sport=.20,race=.60}) do
 local budget=E.aeroBudget(1000,10,20,kit)
 near(budget.maxKG,1000*share)
 local zero=E.aeroSetting(budget,0,0)
 near(zero.frontKG,10);near(zero.rearKG,20);near(zero.extraDragN,0)
 local max=E.aeroSetting(budget,1e6,1e6)
 near(max.frontKG+max.rearKG,budget.maxKG)
 near(max.extraDragN,(budget.maxKG-30)*E.G/budget.liftDrag)
 local stock=E.aeroBudget(1000,400,500,kit)
 near(stock.maxKG,900);near(stock.extraKG,0)
 local over=E.aeroSetting(stock,1e6,1e6)
 near(over.frontKG,400);near(over.rearKG,500)
end
print('upgrade effects: passed')
