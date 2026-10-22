-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local N=require('ge/extensions/raceprep/nativeWeight')
local catalog={parts={},nativeBodies={models={car={holderSlot='car_mod',holder='rp_native_a_holder',bodySlot='rp_body_a'}}}}
catalog.parts.rp_native_a_holder={native=true,kind='bodyHolder',model='car'}
for _,st in ipairs(N.STAGES) do if st.key~='stock' then catalog.parts['rp_body_a_'..st.key]={native=true,kind='body',model='car',stage=st.key,scale=st.scale} end end
local tree={chosenPartName='car',children={car_mod={id='car_mod',chosenPartName='',children={}},paint={chosenPartName='paint_blue',children={}}}}
local d={config={model='car',partsTree=tree,vars={pressure=30}},vdata={model='car',powertrain={{type='combustionEngine'}},activeParts={}}}
assert(N.available(d,catalog) and #N.rows(d,catalog,1000)==4)
assert(N.native({vdata={model='car'}},catalog),'Known native model stays isolated while its engine rebuilds')
assert(N.rows(d,catalog,1000)[4].kg==150 and N.rows(d,catalog,1000)[4].bonus==nil)
assert(not N.native({vdata={powertrain={{type='camsoEngine'},{type='combustionEngine'}}}}),'Mixed export excluded')
local fitted=N.applyTree(tree,catalog,'car','race')
assert(fitted.children.car_mod.chosenPartName=='rp_native_a_holder')
assert(fitted.children.car_mod.children.rp_body_a.chosenPartName=='rp_body_a_race')
assert(tree.children.car_mod.chosenPartName=='' and fitted.children.paint.chosenPartName=='paint_blue','Original and unrelated slots preserved')
local conflict=N.applyTree({children={car_mod={chosenPartName='third_party_mod',children={}}}},catalog,'car','race')
assert(not conflict,'Never replace an unrelated Additional Modification')
local reverted=N.applyTree(fitted,catalog,'car','stock');assert(reverted.children.car_mod.chosenPartName=='')
catalog.parts.native_aero={native=true,kind='aero',model='car'}
fitted.children.car_mod.chosenPartName='native_aero'
reverted=N.applyTree(fitted,catalog,'car','stock');assert(reverted.children.car_mod.chosenPartName=='native_aero','Retain future native aero holder')
d.vdata.activeParts={body='rp_body_a_race'};d.vdata.raceprepBody={scale=.85}
assert(N.stage(d,catalog).key=='race' and not N.problem(d,catalog))
d.vdata.raceprepBody.scale=.7;assert(N.problem(d,catalog));d.vdata.raceprepBody.scale=.85
jsonReadFile=function(p) if p:find('upgrade%-parts') then return catalog end return {models={}} end
readFile=function() return '{}' end jsonDecode=function() return {models={}} end
core_vehicle_manager={getVehicleData=function() return d end}
local applied,vars
extensions={core_vehicle_partmgmt={setPartsTreeConfig=function(t) applied=t end,setConfigVars=function(t) vars=t end}}
local U=require('ge/extensions/raceprep/upgrades')
local W=require('ge/extensions/raceprep/weight')
local oldRows,oldApply,oldProblem=W.rows,W.applyTree,W.problem
W.rows=function() error('Native vehicle entered Automation rows') end
W.applyTree=function() error('Native vehicle entered Automation applyTree') end
W.problem=function() error('Native vehicle entered Automation problem') end
assert(#U.bodyRows(1,850)==4 and not U.bodyProblem(d))
assert(U.applyWeight(1,'race',{pi=300,class='C'}))
assert(applied.children.car_mod.children.rp_body_a.chosenPartName=='rp_body_a_race')
assert(vars==nil,'Native stages set no Automation tuning variable')
d.config.partsTree=applied;assert(U.undo(1));assert(applied.children.car_mod.chosenPartName=='' and vars.pressure==30)
W.rows,W.applyTree,W.problem=oldRows,oldApply,oldProblem
local allowed,why=U.allowed('body',{parts={body='stock'}},false,true);assert(not allowed and why:find('Factory parts only'))
assert(require('ge/extensions/raceprep/partsRules').groupOf('rp_body_a')=='body')
assert(W.bonusShare({body='rp_body_a_race'})==0,'native race body: no extra PI either')
-- Automation helper receives its original data and output with identical wiring.
d.vdata={model='auto',powertrain={{type='camsoEngine'}}};d.config={model='auto',partsTree={children={camso_tuning_parameters={chosenPartName='',children={}}}}}
catalog.parts.rp_body_b_holder={kind='bodyHolder',model='auto'};catalog.parts.rp_body_b_race={kind='body',model='auto',stage='race'}
catalog.byModel=nil -- parts added in place: drop the per-model index cache (real catalogues are not mutated)
assert(#U.bodyRows(1,1000)==#W.rows(d,catalog,1000))
assert(U.applyWeight(1,'race'));assert(vars[W.VAR]==.85)
assert(applied.children.camso_tuning_parameters.chosenPartName=='rp_body_b_holder')
print('PASS: native body slots, UI rows, Apply/Undo, coexistence, factory rules, bonus; Automation unchanged')
