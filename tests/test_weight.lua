-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local W=require('ge/extensions/raceprep/weight')
-- catalog entries as written by tools/generate_upgrade_body.py (+ an aero kit)
local catalog={parts={
 rp_body_abc123_holder={kind='bodyHolder',model='car'},
 rp_body_abc123_street={kind='body',model='car',stage='street',scale=0.96},
 rp_body_abc123_sport={kind='body',model='car',stage='sport',scale=0.93},
 rp_body_abc123_race={kind='body',model='car',stage='race',scale=0.85},
 rp_aero_abc123_race={kind='aero',model='car',kit='race'}}}
local function stockTree() return {children={main={chosenPartName='car_body',children={camso_tuning_parameters={chosenPartName='',children={}}}}}} end
local function tuning(t) return t.children.main.children.camso_tuning_parameters end
-- fitting a stage without an aero kit uses the holder; stock removes it again
local raced=assert(W.applyTree(stockTree(),catalog,'car','race'))
assert(tuning(raced).chosenPartName=='rp_body_abc123_holder' and tuning(raced).children.rp_body_abc123.chosenPartName=='rp_body_abc123_race')
assert(W.treeStage(raced,catalog,'car')=='race' and W.treeStage(stockTree(),catalog,'car')=='stock')
local back=assert(W.applyTree(raced,catalog,'car','stock'))
assert(tuning(back).chosenPartName=='' and next(tuning(back).children)==nil,'stock = exact stock tree (rating key unchanged)')
assert(tuning(raced).chosenPartName=='rp_body_abc123_holder','input tree not mutated')
-- with an aero kit the stage goes under the kit; a kit change keeps the stage
local kitTree=stockTree();tuning(kitTree).chosenPartName='rp_aero_abc123_race'
local kitRace=assert(W.applyTree(kitTree,catalog,'car','sport'))
assert(tuning(kitRace).chosenPartName=='rp_aero_abc123_race' and tuning(kitRace).children.rp_body_abc123.chosenPartName=='rp_body_abc123_sport')
local noKit=stockTree() -- what changedTree gives when the kit is removed
local carried=W.carry(kitRace,noKit,catalog,'car')
assert(tuning(carried).chosenPartName=='rp_body_abc123_holder' and W.treeStage(carried,catalog,'car')=='sport','stage survives removing the kit')
assert(W.carry(stockTree(),kitTree,catalog,'car')==kitTree,'no stage: nothing to carry')
-- Automation's own advanced tuning part is not replaced silently
local adv=stockTree();tuning(adv).chosenPartName='camso_tuning_parameters'
local none,why=W.applyTree(adv,catalog,'car','race');assert(none==nil and why:find('advanced tuning'))
assert(W.applyTree(stockTree(),catalog,'other','race')==nil,'cars without generated parts')
-- fitted stage from installed parts; the value must match the part
local function car(parts,var,val)
 return {config={model='car',partsTree=stockTree(),vars={['$nodeWeightScale']=var}},vdata={model='car',activeParts=parts,
  variables=val and {['$nodeWeightScale']={default=val,val=val}} or {}}}
end
assert(W.available(car({},nil,nil),catalog) and not W.available({config={model='x',partsTree=stockTree()},vdata={}},catalog))
assert(W.stage(car({['/a']='rp_body_abc123_race'},nil,0.85),catalog).key=='race' and W.stage(car({},nil,nil),catalog).key=='stock')
assert(W.problem(car({},nil,nil),catalog)==nil,'stock car: variable undefined, nothing to check')
assert(W.problem(car({['/a']='rp_body_abc123_race'},0.85,0.85),catalog)==nil)
assert(W.problem(car({['/a']='rp_body_abc123_race'},0.5,0.85),catalog):find('outside Race Prep'),'config value overriding the part')
assert(W.problem(car({['/a']='camso_tuning_parameters_body'},0.7,1),catalog):find('outside Race Prep'),"Automation's node weight slider")
-- kg per stage from the current mass (fitted stage removed first)
local rows=W.rows(car({['/a']='rp_body_abc123_race'},0.85,0.85),catalog,1275)
assert(rows[4].fitted and rows[4].kg==225 and rows[2].kg==60 and rows[3].kg==105 and rows[1].kg==0,'kg from stock mass 1500')
assert(rows[4].bonus==nil and rows[3].bonus==nil,'no stage adds PI on top of the lower mass (owner 2026-10-21)')
assert(W.bonusShare({a='rp_body_abc123_race'})==0 and W.bonusShare({a='rp_body_abc123_sport'})==0 and W.bonusShare({})==0)
-- "Factory parts only": the body slot is its own group
local PR=require('ge/extensions/raceprep/partsRules')
assert(PR.groupOf('rp_body_abc123')=='body' and PR.groupOf('camso_tuning_parameters')=='aero')
-- hidden structural settings: reset list ignores node weight (body upgrade) and real setup
local S=require('ge/extensions/raceprep/bjr/setup')
local function vars(v) return {config={vars=v},vdata={variables={
 ['$nodeWeightScale']={category='Vehicle Advanced Settings',subCategory='Global',title='Node Weight',min=0.1,max=4,default=1},
 ['$beamDeformScale']={category='Vehicle Advanced Settings',subCategory='Global',title='Beam Deformation',min=0.1,max=4,default=1},
 ['$springRate_F']={category='Suspension',subCategory='Springs',title='Front Spring Rate',min=1000,max=300000,default=34000}}}} end
local changes,count=S.hiddenChanges(vars({['$nodeWeightScale']=0.85,['$beamDeformScale']=4,['$springRate_F']=50000}))
assert(count==1 and changes['$beamDeformScale']==1 and changes['$nodeWeightScale']==nil,'only structural settings reset')
assert(S.hiddenProblem(vars({['$beamDeformScale']=4})):find('reset to car defaults') and S.hiddenProblem(vars({}))==nil)
-- rating: a race-stage car keeps its formula PI (the formula already counts the lower mass), own and remote cars
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
jsonReadFile=function(path)
 if path:find('ratings%-seed') then return {entries={k={model='m',config='c',pi=500,pi_speed=480,pi_technical=520,class='C',source='computed',parts={['/main/x']='rp_body_abc123_race'}}},baselines={['m/c']='k'},constants={}} end
 return {models={},parts={}}
end
readFile=function() return '{}' end;jsonDecode=function() return {models={}} end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local e=R.getConfig('m','c')
assert(e and e.pi==500 and (e.weightBonusPI or 0)==0 and e.class=='C','race stage: formula PI only, got '..tostring(e and e.pi))
-- other drivers see the same PI as the owner (grid / timing tower): bonuses included
R.remoteVehicles={['5']={['5-1']='k'}}
MPVehicleGE={getVehicles=function() return {{ownerID=5,serverVehicleString='5-1',isSpawned=true,gameVehicleID=99}} end,
 getVehicleByGameID=function() return {isLocal=false} end} -- another player's car
local remote=R.getPlayer(5)
assert(remote and remote.pi==500,'remote driver sees the same PI as the owner, got '..tostring(remote and remote.pi))
assert(R.getServerVehicle('5-1').pi==500,'one specific car by server id')
assert(R.getServerVehicle('5-9')==nil,'unknown car: no rating rather than a wrong one')
MPVehicleGE=nil
assert(R.getPlayer(5).pi==500,'single mapped car fallback')
-- vehicle selector: the model tile keeps the default (stock) rating when the
-- player has saved setups next to it (owner's Troglodyte "Race setup")
do
 local model={model={key='m',default_pc='c',Name='Model M'},configs={c={key='c',model_key='m'},mine={key='Race setup',model_key='m'}}}
 core_vehicles={getModel=function() return model end}
 pcall(R.decorateSelector)
 local shown=core_vehicles.getModel('m').model.Name
 assert(shown:find('%[C 500%]'),'model tile shows the stock rating: '..tostring(shown))
 core_vehicles=nil
end
-- F10: upgrade-parts.json is read once, shared between upgrades and raceprepRatings, and indexed by model
do
 package.loaded['ge/extensions/raceprep/upgrades']=nil
 local upgReads=0
 jsonReadFile=function(path)
  if path:find('upgrade%-parts%.json') then upgReads=upgReads+1;return {parts={rp_body_abc123_holder={kind='bodyHolder',model='car'},rp_body_abc123_race={kind='body',model='car',stage='race',scale=0.85}},stocks={}} end
  return {entries={},constants={}}
 end
 local U=require('ge/extensions/raceprep/upgrades')
 dofile('client/lua/ge/extensions/raceprepRatings.lua')
 assert(upgReads==1 and U.catalog.byModel and U.catalog.byModel.car and U.catalog.byModel.car.rp_body_abc123_race,'upgrade-parts.json loaded once and indexed by model')
end
-- generated files: every car has holder + 3 stages, every aero kit carries the body slot
local catalogFile=io.open('client/lua/ge/extensions/raceprep/upgrade-parts.json'):read('*a')
local holders=select(2,catalogFile:gsub('"kind": "bodyHolder"',''));local stages=select(2,catalogFile:gsub('"kind": "body"',''))
-- the fleet grows when cars are added on the server: every car, 3 stages each
-- the public tree ships an empty catalogue (parts are generated per server)
assert(stages==holders*3,'body parts per car: '..holders..' / '..stages)
print('PASS: body stages as parts (holder, kit carry, stock tree restored), value check, factory group, no extra race PI')
