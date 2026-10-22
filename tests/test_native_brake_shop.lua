-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local function clone(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=clone(v) end return o end
local function equal(a,b) if type(a)~=type(b) then return false end if type(a)~='table' then return a==b end for k,v in pairs(a) do if not equal(v,b[k]) then return false end end for k in pairs(b) do if a[k]==nil then return false end end return true end
local catalog={parts={},stocks={},nativeTyres={sources={['car/factory_tire']={native=true,model='car',part='factory_tire',
 slotType='tire_F_16x7',axle='front',nominalWidthMM=205,tireWidthMM=185,compound='sport',variants={}}}}}
for _,level in ipairs({'sport','race'}) do
 catalog.parts['rp_brake_'..level]={native=true,kind='brake',model='car',stockPart='factory_brake',slotType='car_brake_F',
  name=level,level=level,torqueScale=level=='sport' and 1.15 or 1.30,coolingScale=1,pads='factory'}
end
catalog.parts.auto_sport={kind='brake',name='Auto Sport',level='sport',torqueScale=1.15,coolingScale=1.2,pads='sport'}
jsonReadFile=function(path) if path:find('upgrade%-parts') then return catalog end return {models={}} end
readFile=function() return '{}' end jsonDecode=function() return {models={}} end
local tree={chosenPartName='main',children={car_brake_F={id='car_brake_F',chosenPartName='factory_brake',children={}},
 tire_F_16x7={id='tire_F_16x7',chosenPartName='factory_tire',children={}}}}
local d={config={model='car',partsTree=tree,vars={['$brakestrength']=1}},
 vdata={model='car',powertrain={{type='combustionEngine'}},activePartsData={main={slots={{'type','default','description'},
 {'car_brake_F','factory_brake','Front brakes'},{'tire_F_16x7','factory_tire','Front tyres'}}}}}}
core_vehicle_manager={getVehicleData=function() return d end}
local applied
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t end,setConfigVars=function() end},core_vehicle_manager=core_vehicle_manager}
local U=require('ge/extensions/raceprep/upgrades')
local function compatible(slot) if slot.type=='car_brake_F' then return {'factory_brake','factory_race','rp_brake_sport','rp_brake_race'} end return {'factory_tire','factory_other'} end
local rows=U.list(1,compatible)
assert(#rows==2,'Native tyre AND brake row must coexist')
local brake,tyre
for _,r in ipairs(rows) do if r.nativeTyre then tyre=r elseif r.slot=='car_brake_F' then brake=r end end
assert(tyre and brake and brake.group=='suspension')
assert(#brake.options==4 and brake.options[1].name=='factory_brake','Factory and RP brake choices coexist')
local foundFactory=false for _,o in ipairs(brake.options) do if o.name=='factory_race' then foundFactory=true end end
assert(foundFactory,'Real compatible factory brakes stay available')
assert(#tyre.options==2,'Factory tyres join the existing native tyre row')
local label,tip=U.partEffect(1,'rp_brake_race')
assert(label:find('+30 %%') and not tip:find('150'),'No Automation Race brake tuning claim for native')
assert(U.apply(1,brake,'rp_brake_race',{pi=300,class='C'}));d.config.partsTree=applied
local fitted=U.list(1,compatible)
for _,r in ipairs(fitted) do if r.slot=='car_brake_F' then assert(#r.options==4,'factory and RP choices remain after fitting') end end
assert(U.undo(1) and applied.children.car_brake_F.chosenPartName=='factory_brake')
local allowed,why=U.allowed('suspension',{parts={suspension='stock'}},false,true)
assert(not allowed and why:find('Factory parts only'))
-- Native pad defaults cannot override a better fitted factory pad. The new
-- brake retains the same pad slot and applies the minimum as a real part.
d.config.partsTree=clone(tree)
catalog.parts.rp_brake_race.padSlots={{id='brakepad_F',default='pad_race',choices={pad_sport='pad_race',pad_carbon='pad_carbon'}}}
d.config.partsTree.children.car_brake_F.children.brakepad_F={id='brakepad_F',chosenPartName='pad_sport',children={}}
local withPads=U.changedTree(d.config.partsTree,brake.path,'rp_brake_race')
assert(withPads.children.car_brake_F.children.brakepad_F.chosenPartName=='pad_race')
d.config.partsTree.children.car_brake_F.children.brakepad_F.chosenPartName='pad_carbon'
withPads=U.changedTree(d.config.partsTree,brake.path,'rp_brake_race')
assert(withPads.children.car_brake_F.children.brakepad_F.chosenPartName=='pad_carbon','Never downgrade a better fitted pad')
d.config.partsTree.children.car_brake_F.children.brakepad_F.chosenPartName='unknown_custom_pad'
assert(U.changedTree(d.config.partsTree,brake.path,'rp_brake_race')==nil,'Unknown custom pads fail safely')
-- Real factory hardware must remain usable without a generated RP catalogue.
local savedModel=d.vdata.model;d.vdata.model='uncovered_native';d.config.model='uncovered_native'
local uncovered=U.list(1,compatible)
assert(#uncovered==2,'Uncovered native models retain factory brake and tyre choices')
for _,row in ipairs(uncovered) do for _,o in ipairs(row.options) do assert(not o.name:match('^rp_'),'Never borrow RP parts from another native model') end end
d.vdata.model=savedModel;d.config.model=savedModel
-- Automation list must be identical with/without any native catalogue rows.
d.config={model='automation',partsTree={chosenPartName='auto_main',children={Camso_brake_F={chosenPartName='auto_stock',children={}}}}}
d.vdata={model='automation',powertrain={{type='camsoEngine'}},activePartsData={auto_main={slots={{'type','default','description'},{'Camso_brake_F','auto_stock','Front brakes'}}}}}
local function autoCompatible() return {'auto_stock','auto_sport'} end
local before=U.list(1,autoCompatible)
local saved=catalog.nativeTyres;catalog.nativeTyres=nil
local a,b=catalog.parts.rp_brake_sport,catalog.parts.rp_brake_race;catalog.parts.rp_brake_sport,catalog.parts.rp_brake_race=nil,nil
local after=U.list(1,autoCompatible)
assert(#before==1 and equal(before,after),'Automation list is unchanged by native categories')
catalog.nativeTyres=saved;catalog.parts.rp_brake_sport,catalog.parts.rp_brake_race=a,b
print('PASS: native factory/RP tyres and brakes coexist, apply/undo/rules; Automation unchanged')
