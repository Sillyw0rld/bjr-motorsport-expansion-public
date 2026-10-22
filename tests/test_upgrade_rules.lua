-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race rules for upgrades (Motorsport settings > Race rules > Upgrades, 2026-10-21):
-- caps on what a car may have fitted, on top of class / PI
package.path='client/lua/?.lua;'..package.path
local R=dofile('client/lua/ge/extensions/raceprep/upgradeRules.lua')
-- engine levels follow the packages: Stage 1 Street, Stage 2 Sport, Stage 3 Race
assert(R.engineRank({intake='sport'})==1 and R.engineRank({ecu='race'})==2 and R.engineRank({cam='sport'})==2)
assert(R.engineRank({cam='race'})==3 and R.engineRank({forged=true})==3 and R.engineRank({displacement='sport'})==3)
assert(R.engineRank({induction='turbo_small'})==nil and R.engineRank({radiator='race'})==nil,'induction and cooling have their own rules')
assert(R.compoundClass('standard')=='road' and R.compoundClass('sport')=='sport' and R.compoundClass('semi_slick')=='semi' and R.compoundClass('race_soft')=='slick')
-- no rules: everything allowed (old rules files have no upgrades table)
for _,item in ipairs({{kind='engine',rank=3},{kind='induction'},{kind='cooling'},{kind='engineConversion'},{kind='drivetrainConversion',layout='AWD'},
 {kind='tyre',compound='race_soft',offset=40},{kind='body',stage='race'},{kind='brake',level='race'},{kind='aero'},{kind='nitrous'}}) do
 assert(R.block({},item)==nil and R.block(nil,item)==nil,'default allows '..item.kind)
end
local r={upgrades={engine='sport',induction='factory',engineConversion=false,drivetrainConversion='fwdrwd',compound='semi',width=20,weight='street',brakes='sport',radiators=false},aero=false,nitrous=false}
assert(R.block(r,{kind='engine',rank=2})==nil and R.block(r,{kind='engine',rank=3})=='Race rules: engine parts max Sport')
assert(R.block(r,{kind='induction',factory=true})==nil and R.block(r,{kind='induction'})=='Race rules: factory forced induction only')
assert(R.block({upgrades={induction='none'}},{kind='induction',factory=true})=='Race rules: no forced induction')
assert(R.block(r,{kind='cooling'})=='Race rules: no radiator or cooler upgrades')
assert(R.block(r,{kind='engineConversion'})=='Race rules: no engine conversions')
assert(R.block(r,{kind='drivetrainConversion',layout='RWD'})==nil and R.block(r,{kind='drivetrainConversion',layout='AWD'})=='Race rules: FWD and RWD conversions only')
assert(R.block({upgrades={drivetrainConversion='off'}},{kind='drivetrainConversion',layout='RWD'})=='Race rules: no drivetrain conversions')
assert(R.block(r,{kind='tyre',compound='semi_slick',offset=20})==nil)
assert(R.block(r,{kind='tyre',compound='race_hard',offset=0})=='Race rules: tyres max Semi-slick')
assert(R.block(r,{kind='tyre',compound='sport',offset=40})=='Race rules: tyres up to +20 mm')
assert(R.block(r,{kind='tyre',compound='sport',offset=-20})==nil,'narrower is always allowed')
assert(R.block({upgrades={width=0}},{kind='tyre',compound='sport',offset=20})=='Race rules: no wider tyres')
assert(R.block(r,{kind='body',stage='street'})==nil and R.block(r,{kind='body',stage='sport'})=='Race rules: weight reduction max Street')
assert(R.block({upgrades={weight='none'}},{kind='body',stage='street'})=='Race rules: no weight reduction')
assert(R.block(r,{kind='brake',level='sport'})==nil and R.block(r,{kind='brake',level='race'})=='Race rules: brakes max Sport')
assert(R.block({upgrades={brakes='factory'}},{kind='brake',level='sport'})=='Race rules: factory brakes only')
assert(R.block({upgrades={engine='none'}},{kind='engine',rank=1})=='Race rules: no engine upgrades')
assert(R.block(r,{kind='aero'})=='Race rules: stock aero' and R.block(r,{kind='nitrous'})=='Race rules: no nitrous')
-- the first fitted part that breaks a rule is reported, with what is fitted
local why,item=R.violation(r,{{kind='brake',level='sport',title='Sport brakes'},{kind='brake',level='race',title='Race Front Brakes'}})
assert(why=='Race rules: brakes max Sport (Race Front Brakes fitted)' and item.level=='race')
assert(R.violation(r,{{kind='brake',level='sport'}})==nil)
-- BeamNG factory parts mapped to the caps (owner 2026-10-21)
local P=dofile('client/lua/ge/extensions/raceprep/partsRules.lua')
assert(P.factoryRuleItem('pickup_turbo_kit','Turbocharger').kind=='induction')
assert(P.factoryRuleItem('etk_engine_i6_3.0_diesel','3.0L I6 Diesel').kind=='engineConversion')
assert(P.factoryRuleItem('rp_engine_x_cam_race','Race camshaft')==nil and P.factoryRuleItem('','x')==nil,'Race Prep parts and empty slots are not factory swaps')
P.inspect=function() return {native=true,slots={
 {group='engine',id='etk_engine',part='etk_engine_v8',stock='etk_engine_i6',label='4.4L V8'},
 {group='engine',id='etk_intake',part='etk_turbo_stage2',stock='etk_intake',label='Stage 2 Turbo'},
 {group='engine',id='etk_ecu',part='etk_ecu',stock='etk_ecu',label='ECU'},
 {group='drivetrain',id='etk_trans',part='etk_trans_dct',stock='etk_trans_m',label='DCT'}}} end
local items=P.factoryRuleItems(1)
assert(#items==2 and items[1].kind=='engineConversion' and items[2].kind=='induction','only changed factory engine parts; gearbox keeps its own rule')
assert(R.block({upgrades={engineConversion=false}},items[1])=='Race rules: no engine conversions')
assert(R.block({upgrades={induction='factory'}},items[2])=='Race rules: factory forced induction only')
assert(P.factoryPart(1,'etk_engine')=='etk_engine_i6')
P.inspect=function() return {native=false,slots={{group='engine',id='Camso_Engine',part='a',stock='b'}}} end
assert(#P.factoryRuleItems(1)==0 and P.factoryPart(1,'Camso_Engine')==nil,'Automation cars use the Race Prep classification')
print('PASS: upgrade rules: engine levels match the packages, induction/cooling/conversions/tyres/width/weight/brakes/aero/nitrous caps, first violation')
