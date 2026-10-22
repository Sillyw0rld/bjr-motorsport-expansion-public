-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local R=dofile('client/lua/vehicle/extensions/raceprepPower.lua')
local engine={type='camsoEngine',maxRPM=8000,maxAV=8000*math.pi/30,inertia=.1,
 torqueThrottleMap={[0]={},[50]={},[99]={}},frictionTorqueTable={},FuelUsedThrottleMap={[99]={}},peakPressureCurve={},
 maxTorqueRating=300,maxOverTorqueDamage=1000,tempRevLimiterAV=99999}
for rpm=0,8000 do
 engine.torqueThrottleMap[99][rpm]=200
 engine.torqueThrottleMap[50][rpm]=100
 engine.torqueThrottleMap[0][rpm]=0 -- closed throttle: gross 0, friction slows the engine
 engine.frictionTorqueTable[rpm]=20
 engine.FuelUsedThrottleMap[99][rpm]=1
 engine.peakPressureCurve[rpm]=1
end
engine.frictionTorqueTable[0]=0 -- as camsoEngine: its friction curve starts at {0, 0}
engine.getTorqueData=function(self)
 local curve,maxPower,maxTorque={},0,0
 for rpm,t in pairs(self.torqueThrottleMap[99]) do
  local net=t-(self.frictionTorqueTable[rpm] or 0)
  curve[rpm+1]=net
  if rpm<self.maxRPM then maxTorque=math.max(maxTorque,net);maxPower=math.max(maxPower,net*rpm*math.pi/30/745.699871582) end
 end
 return {maxPower=maxPower,maxTorque=maxTorque,maxRPM=self.maxRPM,curves={{torque=curve}},finalCurveName=1}
end
local spec={stockRevLimit=8000,cam='race',forged=true}
R.applySpec(engine,spec)
assert(engine.maxRPM==9000)
assert(math.abs(engine.torqueThrottleMap[99][3000]-180)<1e-8)
assert(math.abs(engine.torqueThrottleMap[99][7000]-224)<1e-8)
-- past the stock limit (raised by cam/ECU) a closed throttle must still let
-- friction slow the engine: revs hung at the new limit in neutral (1.8.3)
for _,rpm in ipairs({8001,8500,9000}) do
 local net=engine.torqueThrottleMap[0][rpm]-engine.frictionTorqueTable[rpm]
 assert(net<0,'closed throttle above the stock limit: net torque '..net..' at '..rpm)
 local half=engine.torqueThrottleMap[50][rpm]/engine.torqueThrottleMap[99][rpm]
 assert(math.abs(half-.5)<1e-8,'part throttle keeps its share of full throttle above the stock limit')
end
-- camsoEngine's own lookup past the end of the tables (rev limiter
-- overshoot in neutral): t[rpm] or t[#t] or 10. Friction must still slow the
-- engine; 1.8.0-1.8.5 returned the 0 rpm friction (0) and revs hung.
local function camsoFriction(rpm) local t=engine.frictionTorqueTable;return t[rpm] or t[#t] or 10 end
for _,rpm in ipairs({9002,9050,9500,12000}) do
 assert(camsoFriction(rpm)>=19,'friction past the table end at '..rpm..': '..tostring(camsoFriction(rpm)))
 local torque=engine.torqueThrottleMap[0][rpm] or 0
 assert(torque-camsoFriction(rpm)<0,'closed throttle past the table end must slow the engine at '..rpm)
end
local hp=engine:getTorqueData().maxPower
R.applySpec(engine,spec)
assert(math.abs(engine:getTorqueData().maxPower-hp)<1e-8,'curve gain compounded')
spec={stockRevLimit=8000,induction='turbo_small',turboLayout='twin',inductionRace=true}
R.applySpec(engine,spec)
assert(engine.raceprepBoost==0)
assert(math.abs(engine.torqueThrottleMap[99][5000]-200)<1e-8,'lag was already fully boosted')
local full=engine:getTorqueData().curves[1].torque[5001]
assert(math.abs(full-180*1.38)<1e-8,'steady dyno must show full boost')
engine.outputAV1,engine.throttle=5000*math.pi/30,1
powertrain={getDevicesByCategory=function() return {engine} end}
R.updateGFX(.175)
assert(math.abs(engine.raceprepBoost-.5)<1e-8)
assert(math.abs(engine.torqueThrottleMap[99][5000]-200*1.19)<1e-8)
R.updateGFX(.175)
assert(engine.raceprepBoost==1)
assert(math.abs(engine.frictionTorqueTable[5000]-20*1.38)<1e-8)
-- RPM Limit tuned 1000 lower (race ECU): the parts' 9000 becomes 8000
R.applySpec(engine,{stockRevLimit=8000,cam='race',forged=true,revLimitTuning=-1000})
assert(engine.maxRPM==8000,'tuned rev limit honoured: '..engine.maxRPM)
R.applySpec(engine,{stockRevLimit=8000,flywheel='race',stockInertia=.1})
assert(math.abs(engine.inertia-.06)<1e-8)
assert(math.abs(engine.invInertia-1/.06)<1e-8)
print('engine runtime: tuned rev limit, curve reshaping, rev extension, closed throttle above the stock limit, no compounding, transient proxies, steady dyno and inertia passed')
