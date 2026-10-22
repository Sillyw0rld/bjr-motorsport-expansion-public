-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local e={name='mainEngine',type='camsoEngine',maxRPM=2000,
 torqueThrottleMap={[99]={[1000]=200,[2000]=180}},frictionTorqueTable={[1000]=20,[2000]=10},FuelUsedThrottleMap={}}
e.getTorqueData=function(self)
 local curve={}
 for rpm,t in pairs(self.torqueThrottleMap[99]) do curve[rpm]=t-(self.frictionTorqueTable[rpm] or 0) end
 return {maxRPM=2000,curves={{torque=curve}},finalCurveName=1}
end
-- what raceprepPower.applySpec leaves behind: modified maps + the retained stock copy
e._raceprepPowerBase={torque={[99]={[1000]=200,[2000]=180}},friction={[1000]=20,[2000]=10}}
e.torqueThrottleMap={[99]={[1000]=240,[2000]=216}};e.frictionTorqueTable={[1000]=24,[2000]=12}
powertrain={getDevicesByCategory=function() return {e} end}
v={data={nodes={[1]={cid=1,nodeWeight=100,pos={y=-1}},[2]={cid=2,nodeWeight=100,pos={y=1}}},
 wheels={{name='FR',node1=1,node2=1},{name='RR',node1=2,node2=2}}}}
local result
serialize=function(t) result=t;return '{}' end
obj={getNodeMass=function(_,id) return id==1 and 500 or 1000 end,getID=function() return 1 end,queueGameEngineLua=function() end}
local collector=dofile('client/lua/vehicle/extensions/raceprepRating.lua')
collector.snapshot('test')
assert(not result.error,tostring(result.error))
assert(result.mass==1500 and math.abs(result.comY-1/3)<1e-8)
assert(result.engines[1].torque[1][2]==216)
assert(result.stageBaseEngines[1].torque[1][2]==180)
local summary=dofile('client/lua/ge/extensions/raceprep/upgradeEffects.lua').summary(result)
assert(math.abs(summary.frontShare-1/3)<1e-8 and summary.massKG==1500)
print('shop snapshot: actual node mass / split and live versus stock-stage power passed')
