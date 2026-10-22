-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local commands,handlers={},{}
local car={getID=function() return 7 end,getJBeamFilename=function() return 'car' end,queueLuaCommand=function(_,s) commands[#commands+1]=s end}
local d={config={vars={}},vdata={activeParts={},variables={['$fuel']={min=0,max=1,val=.5,default=1,title='Fuel'}}}}
local rules={aero=false,tuning=true,fuel=true,diff=true,trackLimits='off'}
local rt={isServerManaged=function() return true end,getRules=function() return rules end,diffSettings={[7]={}},diffReports={[7]={}},requestDiffReport=function() end}
bjiRacePrep=rt
core_vehicle_manager={getVehicleData=function() return d end}
local writes=0
core_vehicle_partmgmt={setConfigVars=function(values) writes=writes+1;local v={};for k,val in pairs(d.vdata) do v[k]=val end;d.vdata=v;d.config.vars=values end}
package.loaded['ge/extensions/raceprep/bjr/host']={ready=function() return true end,vehicle=function() return car end,editable=function() return true end,tuningEditable=function() return false end,partsEditable=function() return true end,session=function() end,onGrid=function() return false end,notice=function() end,playerID=function() return 1 end}
local engine,tyre=0,0
local U={list=function() return {} end,compoundViolation=function() end,
 allowed=function() return true end,applyPackage=function() engine=engine+1;core_vehicle_partmgmt.setConfigVars({});return true end}
package.loaded['ge/extensions/raceprep/upgrades']=U
raceprepRatings={getVehicle=function() return {class='B',pi=550} end}
package.loaded['ge/extensions/raceprep/partsRules']={violation=function() end}
FS={fileExists=function() return false end};AddEventHandler=function(key,fn) handlers[key]=fn end
serialize=function() return '{}' end;guihooks={trigger=function() end};log=function() end
local readyCount=0;beamjoy_raceRunner={ready=function() readyCount=readyCount+1 end}
local m=dofile('client/lua/ge/extensions/raceprepBJR.lua');m.onUpdate(.1);handlers.RacePrepBJRHostStatus()
package.loaded['ge/extensions/raceprep/bjr/host'].send=function() end
assert(not m.readyProblem())

-- Real action dispatch with BeamNG's replacement semantics (the stub above
-- replaces config.vars rather than recursively merging it).
package.loaded['ge/extensions/raceprep/bjr/host'].tuningEditable=function() return true end
rules.aero=true
d.config.vars={['$frontPSI']=28,['$rearPSI']=31,['$downforceAdjust_F']=100}
d.vdata.variables={
 ['$frontPSI']={min=10,max=50,val=28,default=25,title='Front tyre pressure'},
 ['$rearPSI']={min=10,max=50,val=31,default=25,title='Rear tyre pressure'},
 ['$downforceAdjust_F']={min=0,max=500,val=100,default=40,title='Front downforce',category='Aero'},
 ['$beamDeformScale']={min=.1,max=2,val=1.2,default=1,title='Deform',category='Vehicle Advanced Settings'}}
local function apply(action,payload)
 assert(m.dispatch{action=action,payload=payload or {}})
 local token=assert(commands[#commands]:match('snapshot%("(.-)"%)'))
 m.onFuel(7,token,{{name='tank',energy=300,maxEnergy=1000}})
 m.onUpdate(.2);m.onFuelRestored(7,'restore:'..token)
end
apply('tune',{vars={['$frontPSI']=29}})
assert(d.config.vars['$frontPSI']==29 and d.config.vars['$rearPSI']==31)
apply('tune',{vars={['$rearPSI']=32}})
assert(d.config.vars['$frontPSI']==29 and d.config.vars['$rearPSI']==32)
apply('aeroReset')
assert(d.config.vars['$downforceAdjust_F']==40 and d.config.vars['$frontPSI']==29 and d.config.vars['$rearPSI']==32)
apply('resetHidden')
assert(d.config.vars['$beamDeformScale']==1 and d.config.vars['$frontPSI']==29 and d.config.vars['$rearPSI']==32)
print('PASS: independent tyre pressure Apply, aero reset and structural reset preserve unrelated setup')

-- A centre-split reload must preserve tyre pressures as well.
d.vdata.activeParts={centreDiff='race_centre_diff'}
d.vdata.activePartsData={race_centre_diff={information={name='Race centre differential'}}}
d.vdata.variables['$torquesplit']={min=0,max=1,val=.5,default=.5,title='Centre split'}
rt.diffReports[7]={{name='transferCase',position='centre',frontOutput=1,split=.5,stockSplit=.5}}
rt.applyDiff=function(id,values) rt.diffSettings[id]=values end
rules.centreSplit=true;rules.centreSplitMin=.2;rules.centreSplitMax=.8
apply('diff',{settings={transferCase={mode='stock',frontShare=.6}}})
assert(d.config.vars['$torquesplit']==.6 and d.config.vars['$frontPSI']==29 and d.config.vars['$rearPSI']==32)
print('PASS: centre differential tuning reload preserves independent tyre pressures')
