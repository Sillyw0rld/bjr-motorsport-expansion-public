-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local C=require('ge/extensions/raceprep/engineConversions')
local S=require('common/raceprep/engineSelection')
local U=require('ge/extensions/raceprep/upgrades')
local models={car={stockEngine='stock',stockStructure='stock_structure',stockDefaults={['$revLimitRPM']=6000},
 options={{part='rp_swap_native_engine',structure='new_structure',title='I3 turbo: 172 hp',model='donor',engineKG=80,massDeltaKG=-20,
 resetVars={['$revLimitRPM']=7200},runtime='combustionEngine'}}}}
C.catalog=function() return {models=models} end
local base={parts={},slots={},stockRevLimit=6000}
local donor={parts={},slots={},stockRevLimit=7500}
S.catalog=function() return {models={car=base},swaps={
 rp_swap_native_engine={runtime='combustionEngine'},rp_swap_camso_engine={engineInfo=donor}}} end
assert(S.info('car',{root='stock'})==base)
assert(S.info('car',{root='rp_swap_camso_engine'})==donor)
assert(S.info('car',{root='rp_swap_native_engine'})==nil,'native donor must not get recipient engine effects')
assert(S.info('car',{root='rp_swap_unknown_engine'})==nil,'unknown conversion must not get recipient effects')
local choice=models.car.options[1]
choice.fit={method='automation-bay-envelope',limitSizeXYZ={.9,1,.5}}
assert(C.tooltip('car',choice.part):find('90 × 100 × 50 cm',1,true))
choice.fit={method='stock-block-fallback'}
assert(C.tooltip('car',choice.part):find('original-block',1,true))
assert(C.tooltip('car','stock')==nil)
local tree={chosenPartName='car',children={
 Camso_Engine={chosenPartName='stock',children={
  Camso_Transmission={chosenPartName='race_gearbox',children={finaldrive={chosenPartName='short_fd',children={}}}},
  Camso_engine_structure={chosenPartName='stock_structure',children={Camso_engine_mesh={chosenPartName='original_mesh',children={}}}}}},
 camso_tuning_parameters_engine={chosenPartName='old_hub',children={cam={chosenPartName='old_race_cam'}}},
 Camso_wheels_front={chosenPartName='race_tyres',children={}}}}
local data={config={model='car',partsTree=tree,vars={['$tyrePressure']=28,['$rpBoostGain']=25}},vdata={model='car',
 activeParts={a='stock'},powertrain={{type='camsoEngine'}},activePartsData={car={slots2={
 {name='Camso_Engine',default='stock',coreSlot=true,description='Engine'}}}}}}
core_vehicle_manager={getVehicleData=function() return data end}
local rows=U.list(1,function() return {'stock','rp_swap_native_engine','unapproved_engine'} end,{})
assert(#rows==1 and rows[1].group=='conversion' and rows[1].options[1].title=='Stock engine')
assert(#rows[1].options==2,'unapproved root engines must stay out')
assert(not U.allowed('conversion',{parts={engine='stock'}},false,true),'factory rule blocks conversions')
assert(U.allowed('conversion',{},true,false))
local applied,vars,respawns=nil,nil,0
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t;respawns=respawns+1 end,
 setConfigVars=function(v) vars=v end}}
assert(U.applyMany(1,{{rows[1],'rp_swap_native_engine'}},'Conversion'))
assert(applied.children.Camso_Engine.chosenPartName=='rp_swap_native_engine')
assert(applied.children.Camso_Engine.children.Camso_Transmission.chosenPartName=='race_gearbox')
assert(applied.children.Camso_Engine.children.Camso_Transmission.children.finaldrive.chosenPartName=='short_fd')
assert(applied.children.Camso_Engine.children.Camso_engine_structure.chosenPartName=='new_structure')
assert(applied.children.Camso_Engine.children.Camso_engine_structure.children.Camso_engine_mesh.chosenPartName=='original_mesh')
assert(applied.children.Camso_wheels_front.chosenPartName=='race_tyres')
assert(applied.children.camso_tuning_parameters_engine.chosenPartName=='')
assert(vars['$revLimitRPM']==7200 and vars['$tyrePressure']==28)
assert(vars['$rpBoostGain']==100 and vars['$rpAntiLag']==0,'old engine sliders reset')
assert(tree.children.Camso_Engine.chosenPartName=='stock','source tree untouched')
assert(U.undo(1) and vars['$revLimitRPM']==6000,'Undo restores the previous default even if it was not in config vars')
assert(vars['$rpBoostGain']==25,'Undo restores the previous engine sliders')
assert(applied.children.Camso_Engine.chosenPartName=='stock')
local previous=respawns
local ok,why=U.applyMany(1,{{rows[1],'rp_swap_native_engine'},{{path={'Camso_wheels_front'}},'new_tyres'}},'Batch')
assert(not ok and why:find('separately') and respawns==previous)
local converted=assert(C.change(tree,{'Camso_Engine'},'rp_swap_native_engine','car',{}))
local restored,_,restoreVars=C.change(converted,{'Camso_Engine'},'stock','car',{['$revLimitRPM']=9000})
assert(restored.children.Camso_Engine.children.Camso_engine_structure.chosenPartName=='stock_structure')
assert(restoreVars['$revLimitRPM']==6000 and restored.children.Camso_Engine.children.Camso_Transmission.chosenPartName=='race_gearbox')
print('PASS: conversion list, donor effects, rules, transmission/mesh preservation, variables, Apply, Undo and Stock restore')
models.car.stockFuelTank='original_tank'
choice.fuelTank={part='ethanol_tank'}
tree.children.Camso_FuelTank={id='Camso_FuelTank',chosenPartName='original_tank',children={}}
local convertedTank=assert(C.change(tree,{'Camso_Engine'},choice.part,'car',{}))
assert(convertedTank.children.Camso_FuelTank.chosenPartName=='ethanol_tank')
local stockTank=assert(C.change(convertedTank,{'Camso_Engine'},'stock','car',{}))
assert(stockTank.children.Camso_FuelTank.chosenPartName=='original_tank')
assert(tree.children.Camso_FuelTank.chosenPartName=='original_tank')
local noTank={children={Camso_Engine=tree.children.Camso_Engine}}
local missing,reason=C.change(noTank,{'Camso_Engine'},choice.part,'car',{})
assert(not missing and reason:find('Fuel tank slot'))
