package.path='client/lua/?.lua;'..package.path
local snapshot
serialize=function(v) snapshot=v;return '{}' end
obj={getID=function()return 1 end,getNodeMass=function()return 1000 end,queueGameEngineLua=function()end}
v={data={nodes={{cid=0,pos={y=0}}},wheels={}}}
local original,livePressure,torque={},{},{}
for rpm=0,8000 do original[rpm]=2;livePressure[rpm]=9;torque[rpm]=200 end
local engine={name='mainEngine',type='camsoEngine',maxRPM=8000,peakPressureCurve=livePressure,
 _raceprepPowerBase={pressure=original,torque={[99]=torque},friction={}},raceprepEngineSpec={stockRevLimit=8000}}
engine.getTorqueData=function() return {maxRPM=8000,maxPower=225,maxTorque=200,curves={{torque=torque}},finalCurveName=1}end
powertrain={getDevicesByCategory=function()return {engine}end}
dofile('client/lua/vehicle/extensions/raceprepRating.lua').snapshot('label-test')
assert(not snapshot.error,snapshot.error)
local reference=snapshot.stageBaseEngines[1]
assert(#reference.pressurePoints==81 and reference.pressurePoints[81][2]==2,'snapshot uses original pressure, not modified pressure')
jsonReadFile=function()return {models={},parts={}}end
readFile=function()return '{}'end
jsonDecode=function()return {models={}}end
local U=require('ge/extensions/raceprep/upgrades')
local S=require('common/raceprep/engineSelection')
local C=require('ge/extensions/raceprep/engineConversions');C.catalog=function()return {models={}}end
local info={stockRevLimit=8000,stockForcedInduction=true,slots={induction='boost'},parts={
 boost={slot='boost',title='Race boost upgrade',effect={induction='stock_upgrade',inductionRace=true}},
 forged={slot='internals',title='Race internals',effect={forged=true}}}}
S.catalog=function()return {models={car=info}}end
local data={config={model='car',vars={}},vdata={model='car',activeParts={boost='boost',internals='forged'}}}
core_vehicle_manager={getVehicleData=function()return data end}
raceprepRatings={getLiveCarData=function()return snapshot end,getCarData=function()return snapshot end}
local label,tip,blocked,gain=U.partEffect(1,'boost')
assert(not blocked and gain>10,label)
-- A fitted boost part still displays its gain versus removing that part.
assert(label:find('+17 hp',1,true),label)
reference.pressurePoints=nil
local waiting=U.partEffect(1,'boost')
assert(waiting:find('reading dyno',1,true),'missing boost data must not masquerade as +0 hp')
data.vdata.activeParts.boost=nil
assert(U.partEffect(1,'boost'):find('reading dyno',1,true),'unfitted boost option must wait for pressure too')
print('PASS: boost label receives original pressure curve, shows a real fitted-part gain, and waits for missing data')
