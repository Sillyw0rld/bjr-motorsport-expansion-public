-- SPDX-License-Identifier: AGPL-3.0-or-later
package.path='client/lua/?.lua;'..package.path
local E=require('common/raceprep/engineEffects')
local P=dofile('client/lua/vehicle/extensions/raceprepPower.lua')
local engine={type='camsoEngine',maxRPM=4000,inertia=.1,torqueThrottleMap={[99]={}},frictionTorqueTable={},FuelUsedThrottleMap={[99]={}},peakPressureCurve={},PressureThrottleMap={[99]={},[0]={}}}
for rpm=0,4000 do
 engine.torqueThrottleMap[99][rpm]=220;engine.frictionTorqueTable[rpm]=20;engine.FuelUsedThrottleMap[99][rpm]=1
 engine.peakPressureCurve[rpm]=2;engine.PressureThrottleMap[99][rpm]=2;engine.PressureThrottleMap[0][rpm]=.8
end
engine.getTorqueData=function(self)return{maxPower=self.torqueThrottleMap[99][3000]-self.frictionTorqueTable[3000],maxTorque=200}end
local function apply(target)
 local s={stockRevLimit=4000,stockForcedInduction=true,induction='stock_upgrade',inductionRace=true,forged=true,layout='I4',litres=2,potentialEnabled=true,factoryBoostTarget=target}
 P.applySpec(engine,s);return engine:getTorqueData().maxPower,s
end
local max,s=apply(115);local low=apply(50)
assert(low<max)
assert(engine.PressureThrottleMap[99][3000]==1.5)
assert(engine.peakPressureCurve[3000]==1.5)
assert(engine.PressureThrottleMap[0][3000]==.8,'vacuum retained')
local low2=apply(50);assert(low==low2,'no compounding')
local upper=apply(500);assert(math.abs(upper-max)<1e-8,'cannot exceed maximum target')
assert(engine.PressureThrottleMap[99][3000]==2.15)
local stock=apply(100);assert(engine.PressureThrottleMap[99][3000]==2)
local zero=apply(0);assert(engine.PressureThrottleMap[99][3000]==1 and zero<stock)
assert(E.induction(3000,4000,s,true)==.075,'canonical rating always uses full allowed factory boost')
P.applySpec(engine,{stockRevLimit=4000})
assert(engine.PressureThrottleMap[99][3000]==2,'removing part restores original pressure map')
readFile=function()return 'catalog'end
jsonDecode=function()return{models={car={parts={},stockForcedInduction=true,stockRevLimit=4000}},swaps={}}end
local S=require('common/raceprep/engineSelection')
assert(S.spec('car',{}, {['$rpFactoryBoost']=50},{}).factoryBoostTarget==nil,'stock does not own the control')
local removed=S.spec('car',{}, {},{powertrain={{type='camsoEngine',name='mainEngine'}},mainEngine={turbocharger='turbo'}})
assert(removed.stockForcedInduction==false,'a missing compiled factory device does not select the forced ceiling')
local fitted=S.spec('car',{}, {},{powertrain={{type='camsoEngine',name='mainEngine'}},mainEngine={turbocharger='turbo'},turbo={}})
assert(fitted.stockForcedInduction==true)
local race=S.spec('car',{}, {['$rpFactoryBoost']=50},{raceprepEngine={induction='stock_upgrade',inductionRace=true,forged=true}})
assert(race.factoryBoostTarget==50)
local sport=S.spec('car',{}, {['$rpFactoryBoost']=50},{raceprepEngine={induction='stock_upgrade',forged=true}})
assert(sport.factoryBoostTarget==nil,'non-Race parts do not own the control')
print('PASS: factory Race boost reduces/raises pressure and matching torque/fuel, preserves vacuum, caps at 115%, rates at maximum, restores originals and never compounds')
