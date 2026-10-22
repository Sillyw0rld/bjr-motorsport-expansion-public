-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local function clone(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and clone(v) or v end return o end
deepcopy=clone
local figures={zeroTo60=5,sixtyTo100=8,brake60=40,brake120=160,lat60=1,lat120=1.1}
local cars={
 automation_car={config='stock',measured={zeroTo60=6},model={zeroTo60=5}},
 ['native_car/base_M']={native=true,vehicleModel='native_car',config='base_M',
  measured={zeroTo60=7},model=figures,parts={engine='base',gearbox='manual'}},
 ['native_car/race']={native=true,vehicleModel='native_car',config='race',
  measured={zeroTo60=3},model=figures,parts={engine='race',gearbox='sequential'}}}
jsonReadFile=function(path)
 if path:find('performance%-seed') then return {cars=cars} end
 if path:find('ratings%-seed') then return {entries={},constants={}} end
 return {models={},parts={}}
end
package.loaded['ge/extensions/raceprep/rating']={performance=function() return figures end}
package.loaded['ge/extensions/raceprep/ratingShadow']={build=function() return {} end}
local bundles,tokens={},{}
core_vehicle_manager={getVehicleData=function(id) return bundles[id] end}
core_vehicles={getConfig=function() return {Drivetrain='RWD'} end}
getObjectByID=function(id) return {queueLuaCommand=function(_,code) tokens[id]=assert(code:match('"(stats%-%d+)"')) end} end
serialize=function() return '{}' end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local function request(id,model,config,parts)
 bundles[id]={config={partConfigFilename='/vehicles/'..model..'/'..config..'.pc',vars={}},
  vdata={model=model,activeParts=parts}}
 assert(R.getStats(id)==nil)
 return tokens[id]
end
local function reply(id,token,kind)
 R.onStatic(id,token,{nativeAero={},engineKind={kind=kind,supported=kind~='unknown'}})
 return R.getStats(id)
end
local token=request(1,'native_car','race',{engine='race',gearbox='sequential'})
assert(reply(1,token,'petrol').zeroTo60==3,'native request passes exact factory config')
token=request(2,'native_car','base_M',{engine='base',gearbox='manual'})
assert(reply(2,token,'diesel').zeroTo60==7,'another trim keeps its own anchor')
local fitted={engine='race',gearbox='sequential'}
token=request(3,'native_car','saved',fitted)
fitted.engine,fitted.gearbox='base','manual'
assert(reply(3,token,'electric').zeroTo60==3,'request captures parts rather than using a later mutable tree')
token=request(4,'automation_car','stock',{engine='camsoEngine'})
assert(reply(4,token,'automation').zeroTo60==6,'Automation retains original model-only call')
token=request(5,'other_native','base',{engine='other'})
local estimated=reply(5,token,'petrol')
assert(estimated.zeroTo60==5 and estimated.estimated.zeroTo60,'unmeasured native stays estimated')
print('PASS: actual stats request/reply carries native config and parts; Automation call unchanged')
