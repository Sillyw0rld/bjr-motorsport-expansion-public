-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local U=require('ge/extensions/raceprep/upgrades')
local C=require('ge/extensions/raceprep/engineConversions')
local S=require('common/raceprep/engineSelection')
C.catalog=function() return {models={car={stockEngine='factory',options={{part='rp_swap_native_engine',runtime='combustionEngine'}}}}} end
S.catalog=function() return {models={},swaps={rp_swap_native_engine={runtime='combustionEngine'}}} end
U.partEffect=function() end
local tree={chosenPartName='car',children={Camso_Engine={chosenPartName='rp_swap_native_engine',children={
 rp_swap_native_Camso_Intake={chosenPartName='rp_swap_native_intake_stock',children={}}}}}}
local d={config={model='car',partsTree=tree,vars={}},vdata={model='car',powertrain={{type='combustionEngine'}},
 activeParts={engine='rp_swap_native_engine'},activePartsData={
 car={slots2={{name='Camso_Engine',default='factory',coreSlot=true}}},
 rp_swap_native_engine={slots2={{name='rp_swap_native_Camso_Intake',default='rp_swap_native_intake_stock',coreSlot=true,description='Intake'}}}}}}
core_vehicle_manager={getVehicleData=function() return d end}
local function list()
 return U.list(1,function(slot) return slot.name=='Camso_Engine' and {'factory','rp_swap_native_engine'} or {'rp_swap_native_intake_stock','rp_swap_native_intake_race'} end,
 {rp_swap_native_intake_stock={description='Stock Intake'},rp_swap_native_intake_race={description='Race Intake'}})
end
local row
for _,r in ipairs(list()) do if r.slot=='rp_swap_native_Camso_Intake' then row=r end end
assert(row and #row.options==2,'approved Automation combustionEngine swap retains real donor Race parts')
assert(S.info('car',d.vdata.activeParts)==nil,'native donor does not inherit recipient camso engine effects')
local applied
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t;d.config.partsTree=t end,setConfigVars=function() end}}
assert(U.applyMany(1,{{row,'rp_swap_native_intake_race'}},'Race donor intake'))
assert(applied.children.Camso_Engine.children.rp_swap_native_Camso_Intake.chosenPartName=='rp_swap_native_intake_race')
assert(U.undo(1))
assert(applied.children.Camso_Engine.children.rp_swap_native_Camso_Intake.chosenPartName=='rp_swap_native_intake_stock')
d.vdata.activeParts.engine='unapproved_engine'
for _,r in ipairs(list()) do
 if r.slot=='rp_swap_native_Camso_Intake' then
  for _,o in ipairs(r.options) do assert(o.name=='rp_swap_native_intake_stock','Unapproved RP choices are not offered by the factory-only compatibility path') end
 end
end
print('PASS: approved native-runtime donor upgrades list/apply/Undo; native factory choices do not authorize unapproved RP conversion parts')
