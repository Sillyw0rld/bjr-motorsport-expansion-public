-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local function clone(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and clone(v) or v end return o end
deepcopy=clone
local figures={zeroTo60=5,sixtyTo100=8,brake60=40,brake120=160,lat60=1,lat120=1.1}
local cars={
 automation_car={config='stock',measured={zeroTo60=6},model={zeroTo60=5}},
 ['native_car/base_M']={native=true,vehicleModel='native_car',config='base_M',
  measured={zeroTo60=7,lat60=.9},model=figures,parts={engine='base',gearbox='manual'}},
 ['native_car/race']={native=true,vehicleModel='native_car',config='race',
  measured={zeroTo60=3,lat60=1.4},model=figures,parts={engine='race',gearbox='sequential'}},
}
jsonReadFile=function(path)
 if path:find('performance%-seed') then return {cars=cars} end
 if path:find('ratings%-seed') then return {entries={},constants={}} end
 return {models={},parts={}}
end
readFile=function() return '{}' end
jsonDecode=function() return {models={}} end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local base=R.anchorPerformance('native_car',figures,'base_m',true)
assert(base.measured and base.zeroTo60==7,'case-insensitive exact factory config')
local race=R.anchorPerformance('native_car',figures,'race',true)
assert(race.zeroTo60==3,'different config uses its own rig anchor')
local custom=R.anchorPerformance('native_car',figures,'saved',true,{engine='race',gearbox='sequential'})
assert(custom.measured and custom.zeroTo60==3,'renamed build uses nearest stock parts')
local unknown=R.anchorPerformance('unmeasured_native',figures,'base',true)
assert(not unknown.measured and unknown.estimated.zeroTo60 and unknown.zeroTo60==5)
local automation=R.anchorPerformance('automation_car',figures)
assert(automation.measured and automation.zeroTo60==6,'original model-only path unchanged')
local notNative=R.anchorPerformance('native_car',figures,'race',false)
assert(not notNative.measured and notNative.zeroTo60==5,'native seed never leaks into legacy path')
assert(base.estimated.brake60,'missing native rig figure stays marked estimated')
assert(math.abs(base.lat120-.9*1.1)<1e-9,'existing lateral fallback behavior retained')
print('PASS: native performance config/parts anchors and unchanged Automation behavior')
