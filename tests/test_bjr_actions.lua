-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local commands,handlers={},{}
local requests={}
local car={getID=function() return 7 end,getJBeamFilename=function() return 'car' end,queueLuaCommand=function(_,s) commands[#commands+1]=s end}
local d={config={vars={}},vdata={activeParts={},variables={['$fuel']={min=0,max=1,val=.5,default=1,title='Fuel'}}}}
local rules={aero=false,tuning=true,fuel=true,diff=true,trackLimits='off'}
local rt={isServerManaged=function() return true end,getRules=function() return rules end,diffSettings={[7]={}},diffReports={[7]={}},requestDiffReport=function() end}
bjiRacePrep=rt
core_vehicle_manager={getVehicleData=function() return d end}
local writes=0
core_vehicle_partmgmt={setConfigVars=function(values) writes=writes+1;local v={};for k,val in pairs(d.vdata) do v[k]=val end;d.vdata=v;d.config.vars=values end}
package.loaded['ge/extensions/raceprep/bjr/host']={send=function(event,p) requests[#requests+1]={event=event,payload=p} end,ready=function() return true end,vehicle=function() return car end,editable=function() return true end,tuningEditable=function() return false end,partsEditable=function() return true end,session=function() end,onGrid=function() return false end,notice=function() end,playerID=function() return 1 end}
local engine,tyre=0,0
local U={list=function() return {} end,compoundViolation=function() end,
 allowed=function() return true end,applyPackage=function() engine=engine+1;core_vehicle_partmgmt.setConfigVars({});return true end}
package.loaded['ge/extensions/raceprep/upgrades']=U
raceprepRatings={getVehicle=function() return {class='B',pi=550} end}
package.loaded['ge/extensions/raceprep/partsRules']={violation=function() end}
FS={fileExists=function() return false end};AddEventHandler=function(key,fn) handlers[key]=fn end
serialize=function() return '{}' end;guihooks={trigger=function() end};log=function() end
local readyCount=0;beamjoy_raceRunner={ready=function() readyCount=readyCount+1 end}
local m=dofile('client/lua/ge/extensions/raceprepBJR.lua');m.onUpdate(.1);handlers.RacePrepBJRHostStatus();assert(requests[1].event=='RacePrepGetChallenges' and requests[2].event=='RacePrepGetPresets' and requests[3].event=='RacePrepGetProgress','join requests initial server library and profile')
package.loaded['ge/extensions/raceprep/bjr/host'].send=function() end
assert(not m.readyProblem())
-- The actual Ready path enforces the same class/PI limits edited in HTML.
rules.allowedClasses={B=false};assert(m.readyProblem()=='Class B is not allowed.')
rules.allowedClasses.B=true;rules.piMin=551;assert(m.readyProblem():find('below'))
rules.piMin=false;rules.piMax=549;assert(m.readyProblem():find('above'))
rules.piMax=false;assert(not m.readyProblem())
assert(m.dispatch{action='draft',payload={revision=tostring(d.vdata),tune=true}});assert(m.readyProblem():find('Apply'))
beamjoy_raceRunner.ready(true);assert(readyCount==0,'native Ready rejects unapplied browser edits')
beamjoy_raceRunner.ready(false);assert(readyCount==1,'native Unready still works')
m.dispatch{action='discard'};assert(not m.readyProblem())
-- Fixed-car tuning disabled: independent fuel change and JBeam fuel still work.
local token;for _,cmd in ipairs(commands) do token=cmd:match('snapshot%("(.-)"%)') or token end;assert(token)
m.onFuel(7,token,{{name='tank',energyType='gasoline',energy=200,maxEnergy=1000}})
assert(m.dispatch{action='fuel',payload={name='tank',percent=30}})
assert(m.dispatch{action='tune',payload={vars={['$fuel']=.25}}})
assert(writes==0,'waits for fresh VE snapshot before reload')
local capture=commands[#commands]:match('snapshot%("(.-)"%)')
m.onFuel(7,capture,{{name='tank',energy=300,maxEnergy=1000}})
assert(writes==1 and m.readyProblem():find('restoring fuel'))
m.onUpdate(.2);assert(commands[#commands]:find('apply',1,true),'post-rebuild fuel restored once')
assert(m.readyProblem():find('restoring fuel'),'Ready waits for VE acknowledgement')
m.onFuelRestored(7,'restore:'..capture)
assert(not m.readyProblem())
local before=#commands;m.onFuel(7,capture,{});assert(#commands==before,'late snapshot cannot repeat operation')
-- BJR's grid teleport resets the car (full tanks): the chosen 30 % comes back
-- in the countdown, but a reset during the race is left alone.
local host=package.loaded['ge/extensions/raceprep/bjr/host'];local hostSession=host.session
host.session=function() return {state='COUNTDOWN'} end
before=#commands;m.onVehicleResetted(7);m.onUpdate(.5)
local reapplied=false;for i=before+1,#commands do reapplied=reapplied or commands[i]:find('raceprepFuel.applyPercent',1,true)~=nil end
assert(reapplied,'fuel re-applied after the grid teleport reset')
host.session=function() return {state='RACE'} end
before=#commands;m.onVehicleResetted(7);m.onUpdate(.5)
for i=before+1,#commands do assert(not commands[i]:find('raceprepFuel.applyPercent',1,true),'no refill trick during the race') end
host.session=hostSession
-- Engine package goes through the real action and fresh capture/rebuild path.
assert(not m.dispatch{action='enginePackage',payload={number=4}})
assert(m.dispatch{action='enginePackage',payload={number=2}})
capture=commands[#commands]:match('snapshot%("(.-)"%)')
m.onFuel(7,capture,{{name='tank',energy=300,maxEnergy=1000}});assert(engine==1)
m.onUpdate(.2);m.onFuelRestored(7,'restore:'..capture)
-- Dedicated tyre action builds one tree for front + mirrored rear slick.
local front={slot='Camso_wheels_front',current='front_stock',path={'f'}},rear
rear={slot='Camso_wheels_rear',current='rear_stock',path={'r'}}
U.list=function() return {front,rear} end
U.COMPOUNDS={'stock','sport','race_soft'}
U.slickOf=function(c) return c and c:match('^race_(%a+)$') end
U.slickAllowed=function(r,c) return not c or not r.slickCompounds or r.slickCompounds[c]~=false end
U.catalog={stocks={['car/front']={part='front_stock',widthMM=200,compound='sport'},['car/rear']={part='rear_stock',widthMM=220,compound='race_hard'}},parts={
 front_soft={kind='tyre',model='car',stockPart='front_stock',compound='race_soft',offsetMM=40},
 rear_soft={kind='tyre',model='car',stockPart='rear_stock',compound='race_soft',offsetMM=0}}}
U.fittedTyres=function() return {front={part='front_stock',compound='sport'},rear={part='rear_stock',compound='race_hard'}} end
U.applyMany=function(_,changes) tyre=tyre+1;assert(#changes==2 and changes[1][2]=='front_soft' and changes[2][2]=='rear_soft');core_vehicle_partmgmt.setConfigVars({});return true end
assert(m.dispatch{action='tyre',payload={axle='front',compound='race_soft',offset=40}})
capture=commands[#commands]:match('snapshot%("(.-)"%)')
m.onFuel(7,capture,{{name='tank',energy=300,maxEnergy=1000}});assert(tyre==1)
m.onUpdate(.2);m.onFuelRestored(7,'restore:'..capture)
-- Apply upgrades: pending parts + both axles' tyres in ONE reload; pending blocks Ready
do
 local intake={slot='Camso_Intake_x',group='engine',title='Intake',current='intake_stock',path={'i'},options={{name='intake_stock'},{name='intake_sport'},{name='intake_bad',unsafe='Too heavy'}}}
 U.list=function() return {front,rear,intake} end
 U.catalog.parts.rear_soft40={kind='tyre',model='car',stockPart='rear_stock',compound='race_soft',offsetMM=40}
 local batches={}
 U.applyMany=function(_,changes,label) batches[#batches+1]={changes=changes,label=label};core_vehicle_partmgmt.setConfigVars({});return true end
 assert(m.dispatch{action='draft',payload={revision=tostring(d.vdata),upgrades=true}});assert(m.readyProblem():find('upgrade'),'pending upgrades block Ready')
 assert(m.dispatch{action='upgrades',payload={parts={{index=3,name='intake_sport'}},tyres={{axle='front',compound='race_soft',offset=40},{axle='rear',compound='race_soft',offset=40}}}})
 capture=commands[#commands]:match('snapshot%("(.-)"%)')
 m.onFuel(7,capture,{{name='tank',energy=300,maxEnergy=1000}})
 assert(#batches==1,'one reload for all upgrades')
 local names={};for _,c in ipairs(batches[1].changes) do names[#names+1]=c[2] end
 assert(table.concat(names,',')=='intake_sport,front_soft,rear_soft40',table.concat(names,','))
 m.onUpdate(.2);m.onFuelRestored(7,'restore:'..capture)
 assert(not m.dispatch{action='upgrades',payload={parts={{index=3,name='intake_bad'}}}},'unsafe part refused')
 U.catalog.parts.rear_med={kind='tyre',model='car',stockPart='rear_stock',compound='race_medium',offsetMM=0}
 U.COMPOUNDS={'stock','sport','race_soft','race_medium'}
 assert(not m.dispatch{action='upgrades',payload={tyres={{axle='front',compound='race_soft',offset=40},{axle='rear',compound='race_medium',offset=0}}}},'mixed slicks refused')
 assert(not m.dispatch{action='upgrades',payload={}},'nothing to apply')
 U.list=function() return {front,rear} end
end
print('PASS: Apply upgrades fits parts and both axles in one reload; mixed slicks and unsafe parts refused')
-- Applied aero changes cannot bypass Ready even without a kit part.
d.vdata.variables['$bodyDragCoef']={min=0,max=1,val=.7,default=.3};assert(m.readyProblem():find('Aero must be stock'))
d.vdata.variables['$bodyDragCoef']=nil
-- New result receipt requests one automatic review, without duplicate reopening.
jsonDecode=function(v) return v end
m.onResults{runID='r1',rows={}};assert(m.visible and m.tab=='results')
m.visible=false;m.onResults{runID='r1',rows={}};assert(not m.visible)
m.onResults{runID='r2',rows={}};assert(m.visible)
-- The level control uses the original normalized TrackSet amount; permissions
-- remain enforced in Lua even if a browser bypasses its disabled button.
local trackCalls=0
package.loaded['ge/extensions/raceprep/director']={data={track={level='testmap'}},setTrack=function(p) trackCalls=trackCalls+1;assert(p.amount==.7) end}
package.loaded['ge/extensions/raceprep/bjr/host'].canEdit=function() return false end
m.dispatch{action='track',payload={amount=.7}};assert(trackCalls==0)
package.loaded['ge/extensions/raceprep/bjr/host'].canEdit=function() return true end
m.dispatch{action='track',payload={amount=.7}};assert(trackCalls==1)
print('PASS: real BJR actions, native dirty Ready guard, Unready, fixed-car fuel, async capture/reload/restore, late callbacks, stock aero and one-shot results review')
-- Clear a scoped override by sending an explicit false through the same API.
getCurrentLevelIdentifier=function() return 'testmap' end
beamjoy_races={data={{id=1,name='Race'}}}
local scopeCount=0
rt.sendRules=function(scope,r) scopeCount=scopeCount+1;assert(scope=='testmap:1' and r==false) end
assert(m.dispatch{action='rules',payload={scope='1',rules=false}});assert(scopeCount==1)
package.loaded['ge/extensions/raceprep/bjr/host'].canEdit=function() return false end
m.dispatch{action='rules',payload={scope='1',rules=false}};assert(scopeCount==1)
-- Extra engine slots use the original generated hub and fresh fuel capture.
U.engineInfo=function() return {hub='compatible_hub'} end
U.list=function() return {{slot='camso_tuning_parameters_engine',current='',options={{name='compatible_hub'}}}} end
local hubApplied=0
U.apply=function(_,row,part) assert(row.slot=='camso_tuning_parameters_engine' and part=='compatible_hub');hubApplied=hubApplied+1;core_vehicle_partmgmt.setConfigVars({});return true end
assert(m.dispatch{action='engineSlots'})
local hubToken=commands[#commands]:match('snapshot%("(.-)"%)')
m.onFuel(7,hubToken,{{name='tank',energy=300,maxEnergy=1000}});assert(hubApplied==1)
print('PASS: scoped override clearing/permission and compatible engine-hub action')

-- Server save actions fail closed with a specific bridge/loading message.
package.loaded['ge/extensions/raceprep/bjr/host'].canEdit=function() return true end
m.onUpdate(6)
assert(not m.dispatch{action='track',payload={amount=.7}})
assert(trackCalls==1,'stale bridge must not dispatch track changes')
assert(not m.dispatch{action='rules',payload={scope='1',rules=false}})
assert(scopeCount==1,'stale bridge must not dispatch rules changes')
handlers.RacePrepBJRHostStatus()
package.loaded['ge/extensions/raceprep/director'].data=nil
assert(not m.dispatch{action='track',payload={amount=.7}})
assert(trackCalls==1,'missing server track settings must not be guessed')
print('PASS: stale bridge and missing authoritative track settings block admin writes')

-- F6-F8: closed-window snapshot omits open-window work; U.list cache keyed by
-- vdata (no 5 s rebuild); FS:fileExists and requestDiffReport cached.
do
 package.loaded['ge/extensions/raceprep/director'].yellow=function() end
 rt.aids={}
 U.packageEffect=function() return 'Stage' end;U.packageFitted=function() return false end;U.COMPOUND_LABELS={}
 local listCalls,summaryCalls,fsCalls,diffCalls=0,0,0,0
 U.list=function() listCalls=listCalls+1;return {} end
 U.summary=function() summaryCalls=summaryCalls+1;return {hp=300,massKG=1300,frontShare=.5} end
 FS={fileExists=function() fsCalls=fsCalls+1;return false end}
 rt.requestDiffReport=function() diffCalls=diffCalls+1 end
 m.dispatch{action='show',payload={value=false}}
 local closed=m.snapshot()
 assert(not closed.visible and closed.car and closed.car.rating.pi==550 and closed.car.summary==nil and closed.parts==nil,'closed snapshot keeps overlay fields only')
 assert(listCalls==0 and summaryCalls==0,'closed snapshot skips U.list and U.summary')
 m.dispatch{action='show',payload={value=true}}
 local open1=m.snapshot()
 assert(open1.visible and open1.car.summary and listCalls==1 and summaryCalls==1)
 m.onUpdate(6);handlers.RacePrepBJRHostStatus()
 m.snapshot()
 assert(listCalls==1,'U.list stays cached across >5 s when vdata is unchanged')
 for _=1,5 do m.onUpdate(1.1);handlers.RacePrepBJRHostStatus() end
 assert(fsCalls==0 and diffCalls==0,'FS:fileExists and requestDiffReport cached across 1 s ticks')
 -- Opening via actions.show forces a full snapshot on the next update (<0.5 s)
 local lastPushed
 guihooks={trigger=function(ev,state) if ev=='RacePrepBJRState' then lastPushed=state end end}
 m.dispatch{action='show',payload={value=false}};m.onUpdate(.01)
 assert(lastPushed and not lastPushed.visible and lastPushed.grid==nil,'closed update pushes minimal snapshot')
 m.dispatch{action='show',payload={value=true}};m.onUpdate(.01)
 assert(lastPushed and lastPushed.visible and lastPushed.grid and lastPushed.car.summary and lastPushed.parts,'opening via actions.show pushes full snapshot on next update')
 -- F8: getLiveCarData caches liveSnapshots by vdata (no 5 s re-poll)
 local snapCmds=0
 getObjectByID=function(id) return {getID=function() return id end,queueLuaCommand=function(_,cmd) if cmd:find('raceprepRating%.snapshot') then snapCmds=snapCmds+1 end end} end
 MPVehicleGE={getVehicleByGameID=function() return {isLocal=true} end}
 deepcopy=function(t) return t end
 jsonReadFile=function() return {entries={},constants={},parts={},stocks={}} end
 readFile=function() return '{}' end
 local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
 assert(R.getLiveCarData(7)==nil and snapCmds==1)
 R.onLiveSnapshot(7,'live-1',{mass=1300})
 assert(R.getLiveCarData(7) and R.getLiveCarData(7).mass==1300)
 R.onUpdate(10)
 assert(R.getLiveCarData(7).mass==1300 and snapCmds==1,'liveSnapshots cached across 5 s ticks while vdata unchanged')
 d.vdata={activeParts={},variables={}}
 assert(R.getLiveCarData(7)==nil and snapCmds==2,'vdata change invalidates liveSnapshots and requests once')
 -- F9: classStyle caches JS string and scopes MutationObserver to badged/bracketed elements
 local executedJS
 be={executeJS=function(_,s) executedJS=s end}
 local CS=dofile('client/lua/ge/extensions/raceprep/classStyle.lua')
 CS.injectSelectorBadges()
 assert(executedJS and executedJS:find('#raceprep%-bjr%-root') and executedJS:find("indexOf%('%['%)"),'MutationObserver ignores #raceprep-bjr-root and unbracketed text')
 print('PASS: closed-window snapshot, vdata-keyed U.list cache, and cached FS/diff checks')
end
