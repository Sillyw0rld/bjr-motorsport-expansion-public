-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local S=require('ge/extensions/raceprep/bjr/setup')
local d={config={vars={}},vdata={activeParts={centreDiff='race_centre_diff'},activePartsData={race_centre_diff={information={name='Race centre differential'}}},variables={
 ['$fuel']={type='range',title='Fuel',min=0,max=1,minDis=0,maxDis=100,stepDis=1,val=.4,default=1},
 ['$hidden']={type='range',hideInUI=true,min=0,max=1,val=0},
 ['$rpm']={type='text',min=0,max=10,val=2},
 ['$torquesplit']={type='range',title='Centre split',min=0,max=1,val=.5,default=.5},
 ['$bodyDragCoef']={type='range',min=0,max=2,val=.3,default=.3}
}}}
local vars=S.variables(d,{tuning=false,fuel=true},{editable=true,tuningEditable=false});local by={};for _,m in ipairs(vars) do by[m.name]=m end
assert(not by['$hidden'] and not by['$rpm'])
assert(by['$fuel'].allowed and by['$fuel'].displayValue==40 and S.fromDisplay(by['$fuel'],25)==.25,'fuel editable under tuning lock and units round trip')
d.config.vars['$bodyDragCoef']=.5;assert(S.aeroProblem(d,{aero=false}));d.config.vars={}
local dev={name='centre',position='centre',frontOutput=2,split=.5,stockSplit=.5,preload=100,lock=.4,coast=.2}
local rules={diff=true,centreSplit=true,centreSplitMin=.3,centreSplitMax=.6,maxPreload=150,maxLock=40}
assert(S.front(dev,.7)>.29 and S.front(dev,.7)<.31)
local values,tune,why=S.diffApply(d,rules,{dev},{centre={mode='lsd',preload=999,lock=.9,coast=.2,frontShare=.9}})
assert(values,why);assert(values.centre.preload==150 and values.centre.lock==.4 and math.abs(tune['$torquesplit']-.4)<.0001,'front output 2 maps to native split and clamps')
assert(S.diffProblem(d,rules,{centre={mode='lsd',preload=200}}, {dev}))
d.config.vars['$torquesplit']=.9;assert(S.diffProblem(d,rules,{}, {dev}),'Ready catches changed applied split')
values,tune,why=S.diffApply(d,rules,{dev},{centre={mode='stock'}});assert(values,why);assert(tune['$torquesplit']==.5,'all stock repairs an invalid applied split')
local preset=S.preset('drift',{{name='front',position='front'},{name='rear',position='rear'}})
assert(preset.front.mode=='stock' and preset.rear.mode=='locked')
d.config.vars['$torquesplit']=.5
d.vdata.activePartsData.race_centre_diff.variables={{name='$preload'}}
d.vdata.variables['$preload']={min=0,max=1000,val=200,default=100,title='LSD preload'}
assert(S.diffProblem(d,rules,{}, {dev}):find('preload'),'generic JBeam preload cannot bypass the race maximum')
local locked=S.variables(d,{diff=false},{editable=true,tuningEditable=true});for _,m in ipairs(locked) do if m.name=='$preload' then assert(not m.allowed) end end
print('PASS: setup units, hidden settings, fixed-car fuel, aero validation, differential limits, split orientation/reload and stock repair')
local defaults=S.preset('race',{{name='rear',position='rear'}})
assert(defaults.rear.preload==150 and defaults.rear.lock==.45 and defaults.rear.coast==.25,'original race LSD preset')
d.vdata.raceprepAero={};d.vdata.variables['$rpAeroFront']={title='Front downforce',min=0,max=1000,val=100,default=100}
local separate=S.variables(d,{tuning=false,aero=true},{editable=true,tuningEditable=true})
for _,v in ipairs(separate) do if v.name=='$rpAeroFront' then assert(v.allowed,'independent Aero rule is not blocked by Setup tuning rule') end end
-- Car files rarely give a step: derive one from the range, never a flat 0.01
assert(S.step({},1000,300000)==100,'spring rate step')
assert(math.abs(S.step({},0.995,1.005)-1e-5)<1e-12,'toe gets fine steps')
assert(S.step({step=0.5},0,10)==0.5,'explicit step kept')
for _,v in ipairs(separate) do if v.name=='$rpAeroFront' then assert(v.step==1,'aero step from range') end end
print('PASS: setup step from range')
-- Setup sections on a real Automation export (Arrow AWD 2.0 variables)
local real={
 {'$frontPSI','Tyres','','Front Tyre Pressure','tyres','front'},
 {'$gear_1_race','Gearing','Transmission','Gear 1','gearing'},
 {'$finaldrive_r','Gearing','Differentials','Rear Final Drive','gearing','rear'},
 {'$torquesplit','Gearing','Transfer Case','Torque Split','differential'},
 {'$awdMinLock','Gearing','Transfer Case','Center Coupling Lock','differential'},
 {'$whineMult','Gearing','Transmission','Whine Volume','advanced'},
 {'$CamberFront','Suspension','Alignment','Front Camber','alignment','front'},
 {'$toe_R','Suspension','Alignment','Rear Toe Adjust','alignment','rear'},
 {'$steeringWheelLock','Suspension','Alignment','Steering Wheel Lock','alignment'},
 {'$trackOffset_F','Suspension','Spacing','Front Wheel Offset','alignment','front'},
 {'$brakeOffset_R','Suspension','Spacing','Rear Brake Offset','alignment','rear'},
 {'$swayBarStiffness_F','Suspension','Sway Bars','Front Sway Bar Stiffness','antiroll','front'},
 {'$springRate_R','Suspension','Springs','Rear Spring Rate','springs','rear'},
 {'$RideHeightOffsetFront','Suspension','Springs','Front Ride Height Offset','springs','front'},
 {'$dampRate_rebound_fast_R','Suspension','Dampers','Rear Damper Fast Rebound Rate','damping','rear'},
 {'$BrakePowerFront','Suspension','Brakes','Front Brake Power','brakes','front'},
 {'$lsdpreload_R','Differentials','Rear','Pre-load Torque','differential'},
 {'$downforceAdjust_R','Car Aerodynamics','Downforce','Rear Downforce/Lift Adjust','aero'},
 {'$bodyDragCoef','Vehicle Advanced Settings','BeamNG Aerodynamics','Body drag and buoyancy','aero'},
 {'$revLimitRPM','Engine','RPM Limit','RPM Limit','engine'},
 {'$n2o_power','Nitrous Oxide','','Added Power','engine'},
 {'$torquesplitE','Motor Controller','','Torque Split','engine'},
 {'$dashCamX','Camera Positions','Driver Camera','X Offset','advanced'},
 {'$cabinFilterCoef','Camera Positions','Driver Camera','Interior Sound Deadening','advanced'},
 {'$ffbTune','Force Feedback','','Strength Multiplier','advanced'},
 {'$AfterfireMod','Vehicle Advanced Settings','Engine','Afterfire Modifier','advanced'},
 {'$nodeWeightScale','Vehicle Advanced Settings','Global','Node Weight','hidden'},
 {'$beamDeformScale','Vehicle Advanced Settings','Global','Beam Deformation','hidden'},
 {'$EngineOffsetX','Vehicle Advanced Settings','Engine Offset','Engine Offset X','hidden'},
 {'$tireStiffnessMult_F','Vehicle Advanced Settings','Wheels','Front Tire Stiffness','hidden'},
}
local P=require('ge/extensions/raceprep/tuningPolicy')
for _,r in ipairs(real) do
 local m={category=r[2],subCategory=r[3]~='' and r[3] or nil,title=r[4]}
 local got=S.section(r[1],m,S.diffKind(r[1],m,{}))
 assert(got==r[5],r[1]..' section '..tostring(got)..' expected '..r[5])
 if r[6] then assert(P.axle(r[1],r[4])==r[6],r[1]..' side') end
end
-- personal settings stay free when tuning is off; structural multipliers never open
d.vdata.variables['$ffbTune']={category='Force Feedback',title='Strength Multiplier',min=0,max=2,val=1,default=1}
d.vdata.variables['$nodeWeightScale']={category='Vehicle Advanced Settings',subCategory='Global',title='Node Weight',min=0.1,max=4,val=1,default=1}
local by2={};for _,m in ipairs(S.variables(d,{tuning=false},{editable=true,tuningEditable=true})) do by2[m.name]=m end
assert(by2['$ffbTune'].allowed and by2['$ffbTune'].section=='advanced','force feedback is a personal setting')
assert(not by2['$nodeWeightScale'].allowed and by2['$nodeWeightScale'].section=='hidden','node weight never tunable')
local frozen={};for _,m in ipairs(S.variables(d,{},{editable=false,tuningEditable=false})) do frozen[m.name]=m end
assert(not frozen['$ffbTune'].allowed,'nothing changes while Ready or racing')
-- race suspension unlocks toe and wheel offset like camber
assert(P.role('$toe_F','Front Toe Adjust')=='suspension' and P.role('$trackOffset_F','Front Wheel Offset')=='suspension')
print('PASS: Forza setup sections on real Automation variables')

-- Partial slider payloads must never replace unrelated applied values.
local applied={config={vars={['$frontPSI']=28,['$rearPSI']=31,custom=false}},vdata={variables={
 ['$frontPSI']={val=25,default=24},['$rearPSI']={val=25,default=24},
 ['$springRate_F']={val=45000,default=40000}}}}
local merged=S.mergeVars(applied,{['$frontPSI']=29})
assert(merged['$frontPSI']==29 and merged['$rearPSI']==31 and merged.custom==false)
assert(merged['$springRate_F']==45000,'sparse configs carry the compiled applied value')
assert(applied.config.vars['$frontPSI']==28,'merge never mutates source config')
applied.config.vars=merged
merged=S.mergeVars(applied,{['$rearPSI']=32})
assert(merged['$frontPSI']==29 and merged['$rearPSI']==32,'sequential edits retain both pressures')
print('PASS: full tuning payload retains independent axle settings and sparse compiled values')
