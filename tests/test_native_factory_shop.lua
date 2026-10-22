-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
jsonReadFile=function(path) return path:find('upgrade%-parts') and {parts={},stocks={}} or {models={}} end
readFile=function() return '{}' end
jsonDecode=function() return {models={}} end
local defs={
 {'car_engine','engine_stock','Engine',true},
 {'car_transmission','gear_stock','Transmission',true},
 {'car_differential_R','diff_open','Rear differential',true},
 {'car_spring_F','spring_stock','Front springs',true},
 {'car_brake_F','brake_stock','Front brakes',true},
 {'car_wheel_F','wheel_stock','Front wheels',true},
 {'tire_F_16x7','tire_stock','Front tyres',true},
 {'car_wing_R','','Rear wing',false},
 {'car_abs','','ABS controller',false},
 {'car_swing_arm_R','arm_stock','Rear suspension arm',true},
}
local choices={car_engine={'engine_stock','engine_v8'},car_transmission={'gear_stock','gear_race'},
 car_differential_R={'diff_open','diff_lsd'},car_spring_F={'spring_stock','spring_race'},
 car_brake_F={'brake_stock','brake_race'},car_wheel_F={'wheel_stock','wheel_wide'},
 tire_F_16x7={'tire_stock','tire_race'},car_wing_R={'wing_sport','wing_race'},
 car_abs={'abs_factory'},car_swing_arm_R={'arm_stock','arm_heavy'}}
local tree={chosenPartName='car',children={}}
local slots={}
for _,def in ipairs(defs) do
 slots[#slots+1]={name=def[1],default=def[2],description=def[3],coreSlot=def[4]}
 tree.children[def[1]]={id=def[1],chosenPartName=def[2],children={}}
end
local d={config={model='native_car',partsTree=tree,vars={['$tirepressure_F']=27,['$lsdpreload_R']=60}},
 vdata={model='native_car',powertrain={{type='combustionEngine'}},activePartsData={car={slots2=slots}}}}
core_vehicle_manager={getVehicleData=function() return d end}
local applied,restored
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t end,setConfigVars=function(v) restored=v end}}
local U=require('ge/extensions/raceprep/upgrades')
local rows=U.list(1,function(slot) return choices[slot.name] or {} end)
local bySlot={} for _,row in ipairs(rows) do bySlot[row.slot]=row end
for _,slot in ipairs({'car_engine','car_transmission','car_differential_R','car_spring_F','car_brake_F','car_wheel_F','tire_F_16x7','car_wing_R'}) do
 assert(bySlot[slot] and #bySlot[slot].options>=2,'Missing factory choices: '..slot)
end
assert(bySlot.car_wing_R.group=='aero' and bySlot.car_wing_R.options[1].name=='','Real wing slot supports None')
assert(not bySlot.car_swing_arm_R or bySlot.car_swing_arm_R.group~='aero','Swing arm is not a wing')
assert(not bySlot.car_abs,'No new ABS upgrade category is invented')
assert(U.apply(1,bySlot.car_differential_R,'diff_lsd',{pi=350,class='C'}))
assert(applied.children.car_differential_R.chosenPartName=='diff_lsd')
d.config.partsTree=applied
assert(U.undo(1) and applied.children.car_differential_R.chosenPartName=='diff_open')
assert(restored['$lsdpreload_R']==60 and restored['$tirepressure_F']==27,'Undo retains previous native tuning')
local allowed,reason=U.allowed('drivetrain',{parts={drivetrain='stock'}},false,true)
assert(not allowed and reason:find('Factory parts only'),'Rules still prevent non-factory configurations')
local rules=require('ge/extensions/raceprep/partsRules')
extensions.core_vehicle_manager=core_vehicle_manager
d.config.partsTree=applied
d.config.partsTree.children.car_wing_R.chosenPartName='wing_race'
assert(rules.violation(1,{aero=false}),'Native factory wing changes obey stock-aero race rules')
assert(rules.groupOf('car_wing_R')==nil,'Automation/default grouping path stays unchanged')
-- EVs use the same real chassis/brake/tyre compatibility path.
d.vdata.powertrain={{type='electricMotor'}}
local ev=U.list(1,function(slot) return choices[slot.name] or {} end)
assert(#ev>=8,'Native EV retains factory parts')
print('PASS: real native factory engine/driveline/suspension/brakes/wheels/tyres/aero, optional None, Undo/settings and rules; no ABS invention')
