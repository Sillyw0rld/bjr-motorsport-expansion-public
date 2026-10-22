-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local U=require('ge/extensions/raceprep/upgrades')
local Selection=require('common/raceprep/engineSelection')
local C=require('ge/extensions/raceprep/engineConversions')
C.catalog=function() return {models={}} end
local stock,sport,race='Camso_Intake_demo','rp_engine_demo_intake_sport','rp_engine_demo_intake_race'
local info={stockEngine='Camso_Engine_demo',stockRevLimit=7000,stockInertia=.2,
 slots={intake='Camso_Intake_demo'},parts={
 [sport]={slot='Camso_Intake_demo',effect={intake='sport'}},
 [race]={slot='Camso_Intake_demo',effect={intake='race'}}}}
Selection.catalog=function() return {models={demo=info}} end
U.partEffect=function(_,name) return name==race and 'Race intake' or name==sport and 'Sport intake' or 'Stock intake' end
local tree={chosenPartName='main',children={Camso_Engine={chosenPartName='Camso_Engine_demo',children={
 Camso_Intake_demo={chosenPartName=stock,children={}}}}}}
local d={config={model='demo',partsTree=tree,vars={}},vdata={model='demo',powertrain={{type='camsoEngine'}},activeParts={},activePartsData={
 main={slots2={{name='Camso_Engine',default='Camso_Engine_demo',coreSlot=true}}},
 Camso_Engine_demo={slots2={{name='Camso_Intake_demo',default=stock,coreSlot=true,description='Intake'}}}}}}
core_vehicle_manager={getVehicleData=function() return d end}
local rows=U.list(1,function(slot) return slot.name=='Camso_Intake_demo' and {stock,sport,race} or {'Camso_Engine_demo'} end,{})
local row;for _,r in ipairs(rows) do if r.slot=='Camso_Intake_demo' then row=r end end
assert(row and #row.options==3,'Stock, Sport and generated Race intake are all in the shop')
local applied
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t;d.config.partsTree=t end,setConfigVars=function() end}}
assert(U.applyMany(1,{{row,race}},'Race intake'))
assert(applied.children.Camso_Engine.children.Camso_Intake_demo.chosenPartName==race)
assert(tree.children.Camso_Engine.children.Camso_Intake_demo.chosenPartName==stock,'source tree unchanged')
assert(Selection.spec('demo',{intake=race}).intake=='race','runtime and collector get the existing Race intake effect')
assert(not U.allowed('engine',{parts={engine='stock'}},false,true),'factory-only rule blocks intake upgrade')
assert(U.undo(1))
assert(applied.children.Camso_Engine.children.Camso_Intake_demo.chosenPartName==stock,'Undo restores original intake')
print('PASS: generated Race intake is listed, fits the real slot, feeds Race effects, obeys factory rules and supports Undo')
