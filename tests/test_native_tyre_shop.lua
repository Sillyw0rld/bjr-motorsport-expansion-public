-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local function clone(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and clone(v) or v end return o end
local catalog={parts={},stocks={['automation/front']={part='auto_stock',compound='sport',widthMM=200}},nativeTyres={sources={}}}
local function add(part,axle,slot,width)
 local key='native_car/'..part
 local s={native=true,model='native_car',part=part,axle=axle,slotType=slot,nominalWidthMM=width,tireWidthMM=width-20,
  compound='sport',variants={['race_soft/40']=part..'_race40'}}
 catalog.nativeTyres.sources[key]=s
 catalog.parts[part..'_race40']={native=true,kind='tyre',model='native_car',stockPart=part,axle=axle,slotType=slot,
  compound='race_soft',offsetMM=40,name='Race Soft',nominalWidthMM=width+40,physicsWidthMM=width+20,donorModel='donor'}
end
add('factory_f','front','tire_F_16x7',205)
add('factory_r','rear','tire_R_16x7',225)
add('other_f','front','tire_F_19x9',245)
catalog.parts.non_rp_factory_upgrade={kind='unrelated'}
local tree={chosenPartName='native_main',children={
 suspension={chosenPartName='suspension',children={
  tire_F_16x7={id='tire_F_16x7',chosenPartName='factory_f',children={}},
  tire_R_16x7={id='tire_R_16x7',chosenPartName='factory_r',children={}}}}}}
local d={config={model='native_car',partsTree=tree,vars={pressure=30}},vdata={model='native_car',powertrain={{type='combustionEngine'}}}}
jsonReadFile=function(path)
 if path:find('upgrade%-parts') then return catalog end
 return {models={}}
end
readFile=function() return '{}' end
jsonDecode=function() return {models={}} end
core_vehicle_manager={getVehicleData=function() return d end}
local applied,vars
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t end,setConfigVars=function(v) vars=v end}}
local U=require('ge/extensions/raceprep/upgrades')
local N=require('ge/extensions/raceprep/nativeTyres')
assert(not N.enabled(catalog,'native_car',{powertrain={{type='camsoEngine'}}}),'Automation always excluded')
assert(not N.enabled(catalog,'automation',{}),'no native namespace for Automation')
local rows=U.list(1,function() return {'non_rp_factory_upgrade'} end)
assert(#rows==2 and rows[1].nativeTyre and rows[1].axle=='front')
assert(rows[1].path[1]=='suspension' and rows[1].path[2]=='tire_F_16x7','parts tree path stays native')
assert(#rows[1].options==2 and rows[1].currentTitle=='205 mm Stock (sport)')
assert(rows[1].options[1].name=='factory_f' and rows[1].options[2].name=='factory_f_race40','only matching source upgrades')
assert(U.tyreStock(1,'front').widthMM==205 and U.tyreStock(1,'rear').widthMM==225,'independent axle widths')
assert(U.fittedTyres(1).front.compound=='sport')
assert(U.apply(1,rows[1],'factory_f_race40',{class='C',pi=450}))
assert(applied.children.suspension.children.tire_F_16x7.chosenPartName=='factory_f_race40')
assert(tree.children.suspension.children.tire_F_16x7.chosenPartName=='factory_f','original tree remains for Undo')
d.config.partsTree=applied
assert(U.fittedTyres(1).front.compound=='race_soft' and U.slickPreset(1)=='soft')
assert(U.tyreStock(1,'front').part=='factory_f','upgraded tyre retains exact factory source')
assert(U.compoundViolation(1,{slickCompounds={soft=false}}),'banned slick blocks Ready')
local allowed,why=U.allowed('tyres',{parts={tyres='stock'}},false,true)
assert(not allowed and why:find('Factory parts only'),'factory-parts-only blocks shop changes')
assert(U.undo(1))
assert(applied.children.suspension.children.tire_F_16x7.chosenPartName=='factory_f','Undo restores source tree')
assert(vars.pressure==30,'Undo restores original tuning')
local label,tip=U.partEffect(1,'factory_f_race40')
assert(label=='Race Soft' and tip:find('nominal width 245 mm') and tip:find('contact width 225 mm'))
-- A native factory slick named only "Race" cannot bypass a restricted grade
-- list. Its grip stays unchanged; a named generated grade makes it explicit.
d.config.partsTree=clone(tree)
local front=catalog.nativeTyres.sources['native_car/factory_f']
front.compound,front.compoundReferenceAssumed='race_medium',true
assert(U.fittedTyres(1).front.compound=='race' and U.fittedTyres(1).front.unknownSlickGrade)
assert(U.compoundViolation(1,{})==nil,'unrestricted races still allow unknown factory grades')
assert(U.compoundViolation(1,{slickCompounds={medium=false}}):find('unspecified'),'unknown grade fails closed under compound restrictions')
d.config.partsTree.children.suspension.children.tire_F_16x7.chosenPartName='factory_f_race40'
assert(U.compoundViolation(1,{slickCompounds={medium=false}})==nil,'explicit allowed Soft remains usable')
print('PASS: native-only tyre shop sources, real slots, widths, rules, slick detection and Undo')
