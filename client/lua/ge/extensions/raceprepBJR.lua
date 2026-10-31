-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race Prep's HTML entry point for BeamJoy-Revived. BJR owns grid/ready,
-- vehicle restrictions, timing and race lifecycle. Race Prep adds rules,
-- upgrades, environment and sessions through its own services/events.
local autoWorker
local M={visible=false,tab='setup'}
local Frontend=require('ge/extensions/raceprep/frontend')
local RatingStep=require('ge/extensions/raceprep/ratingStep')
local isCareer
local Career
local H={ready=function() return false end,send=function() end,notice=function() end,session=function() return nil end,_stub=true}
local careerProbeAt=-1e9
local function wallNow()
 local f=Engine and Engine.Platform and Engine.Platform.getSystemTimeMS
 return f and f()/1000 or os.clock()
end
local function bindHost()
 local ok,h=pcall(Frontend.host)
 if ok and type(h)=='table' then H=h end
end
-- A transition can remount the VFS after this extension loads. Keep retrying
-- a negative career marker and bind the workshop broker as soon as it reads.
local function careerMode()
 if Career~=nil then return true end
 local now=wallNow()
 if now-careerProbeAt>2 then
  careerProbeAt=now
  if Frontend.isCareer() then
   local ok,W=pcall(require,'ge/extensions/raceprep/career/workshop')
   if ok and type(W)=='table' then Career=W;isCareer=true end
  end
  if rawget(H,'_stub') then bindHost() end
 end
 return isCareer==true
end
careerMode()
local ClassBuild=require('common/raceprep/classBuild')
local U=require('ge/extensions/raceprep/upgrades')
local Weight=require('ge/extensions/raceprep/weight')
local NativeWeight=require('ge/extensions/raceprep/nativeWeight')
local function bodyAdapter(d) return NativeWeight.native(d,U.catalog) and NativeWeight or Weight end
local P=require('ge/extensions/raceprep/tuningPolicy')
local Setup=require('ge/extensions/raceprep/bjr/setup')
local AutoRatingWorker=require('ge/extensions/raceprep/autoRatingWorker')
local stubRivals={active=function() return false end,view=function() return {} end,rules=function() return nil end,resetLap=function() end,stop=function() end,setGhosts=function() end,update=function() end,draw=function() end,receive=function() end,goToStart=function() return false,'Rivals needs a BeamJoy server.' end}
local stubStrategy={view=function() return {} end,sample=function() end,reset=function() end}
local stubGrid={snapshot=function() return nil end,RATING_FIELDS={}}
local stubSidebar={update=function() end,start=function() end,reset=function() end,stop=function() end}
local stubSelector={wrap=function() return nil end,restore=function() end,reset=function() end,authorize=function() end}
local function mpModule(path,stub)
 local ok,m=pcall(require,path)
 return (ok and type(m)=='table') and m or stub
end
local RivalsSession,Strategy,Grid,Sidebar,Selector
if careerMode() then
 RivalsSession,Strategy,Grid,Sidebar,Selector=stubRivals,stubStrategy,stubGrid,stubSidebar,stubSelector
else
 RivalsSession=mpModule('ge/extensions/raceprep/bjr/rivalsSession',stubRivals)
 Strategy=mpModule('ge/extensions/raceprep/bjr/strategy',stubStrategy)
 Grid=mpModule('ge/extensions/raceprep/bjr/grid',stubGrid)
 Sidebar=mpModule('ge/extensions/raceprep/bjr/sidebar',stubSidebar)
end
local radarEnabled=false
local Library=require('ge/extensions/raceprep/bjr/setupLibrary')
local setupLibrary
local sharedTunesView={items={}}
local sharedTunePending
local function library()
 if not setupLibrary then
  local function path(slot) return '/settings/raceprep/setup-library-'..slot..'.json' end
  setupLibrary=Library.new{read=function(slot) return jsonReadFile and jsonReadFile(path(slot)) end,
   write=function(slot,value) return jsonWriteFile and jsonWriteFile(path(slot),value,true) end,now=os.time}
 end
 return setupLibrary
end

local UR=require('ge/extensions/raceprep/upgradeRules')
-- v2.<minor>.<patch>.<build>, written by build_bjr.py ("dev" when run from source)
local versionInfo=jsonReadFile and jsonReadFile('/lua/ge/extensions/raceprep/version.json') or {}
local pending={tune=false,diff=false,upgrades=false}
local checkedDraft
local draftChoices={}
local draftPreviewChanges={}
local draftRevision
local fuelRows,fuelTargets={},{}
local fuelRequest,fuelSerial,fuelOp,fuelRestore,fuelOwner,fuelSeen
local nextFuel=0
local fuelReapplyAt -- grid teleport reset refilled the tanks: put the chosen levels back
local resultNotice=0
local clock,nextPush,nextKTS,nextDriving=0,0,0,0
local nextTimingError,lastTimingStatus=0,nil
local cachedRows,cachedData={},nil
local drivingIdleSent=nil
local extChecked,diffVdata={},{}
local readyHook,uiReady=false,false
local uiBindings={}
local function restoreReady()
 for _,b in ipairs(uiBindings) do if b.row.callback==b.wrapper then b.row.callback=b.original end end
 uiBindings={}
 if readyHook and readyHook.runner.ready==readyHook.wrapper then readyHook.runner.ready=readyHook.original end
 readyHook=nil
end
local lastError
local handlerRegistered,hostSeen=false,-1e9
local wasReady=false
local lastVehicle
local function runtime() return rawget(_G,'bjiRacePrep') end
local function own() return H.vehicle() end
local function rules()
 if RivalsSession.active() then return RivalsSession.rules() or {} end
 if not H.session() and M.preparedRules then return M.preparedRules end
 local r=runtime();local s=H.session();local selected=s and M.presetLibrary and M.presetLibrary.sessions and M.presetLibrary.sessions[tostring(s.id)]
 return selected and selected.rules or r and r.getRules(s and s.raceId) or {}
end
local function data()
 local v=own();return v and core_vehicle_manager.getVehicleData(v:getID()),v
end
local function reject(text) lastError=text;H.notice(text);return false end
--- may this player do it? (Motorsport settings > Permissions, decided by the
--- server per BeamJoy group: weekend, rules, raceControl); SetConfig until known
local function can(action)
 local rt=runtime();local m=rt and rt.motorsport
 if m and type(m.abilities)=='table' then return m.abilities[action]==true end
 return H.canEdit()
end
M.can=can
--- the race weekend's race rules while it runs on this map (practice,
--- qualifying, grid): the upgrade caps apply in free roam too
M.weekendRules=function()
 local w=require('ge/extensions/raceprep/session').weekend()
 if not w or (w.stage~='practice' and w.stage~='qualifying' and w.stage~='grid') then return nil end
 local level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()
 if w.level and level and tostring(w.level)~=tostring(level) then return nil end
 local rt=runtime();return rt and rt.getRules(w.raceID) or nil
end
--- the race rules the upgrade caps come from: the BJR race being joined
--- (lobby) or the running race weekend's race; nil in plain free roam
local function ruleScope()
 if RivalsSession.active() then return RivalsSession.rules() end
 if H.session() then return rules() end
 if M.preparedRules then return M.preparedRules end
 local w=M.weekendRules and M.weekendRules()
 return w
end
--- why this option cannot be fitted under the race rules (fitted parts never are)
local function ruleBlock(item,current,name)
 local scope=ruleScope();if not scope or not item or name==current then return nil end
 return UR.block(scope,item)
end
local function rating(v) return raceprepRatings and raceprepRatings.getVehicle(v:getID()) end
local function tuning(d)
 return Setup.variables(d,rules(),{editable=H.editable(),tuningEditable=H.tuningEditable()})
end
-- Gear speed inputs for the Setup > Gearing chart: driven-wheel radius, rev
-- limit, and the fitted ratios as a fallback when gears have no tuning sliders.
-- Speeds follow the game's own unit setting (speedometer km/h or mph).
local function gearing(v)
 local r=rawget(_G,'raceprepRatings');local c=r and r.getCarData and r.getCarData(v:getID())
 if type(c)~='table' then return nil end
 local axle=c.drive=='FWD' and 'F' or 'R';local sum,n=0,0
 for _,w in ipairs(c.wheels or {}) do
  if tostring(w.name):sub(1,1):upper()==axle and tonumber(w.radius) then sum,n=sum+w.radius,n+1 end
 end
 local final;for _,f in ipairs(c.finalDrives or {}) do if not f.shaft and (tonumber(f.ratio) or 0)>1 then final=final or f.ratio end end
 local engine=(c.engines or {})[1] or {}
 local imperial=rawget(_G,'settings') and settings.getValue and settings.getValue('uiUnitLength')=='imperial'
 if n==0 or not tonumber(engine.maxRPM) then return nil end
 return {radius=sum/n,rpm=engine.maxRPM,finalDrive=final,gears=((c.gearboxes or {})[1] or {}).forward,unit=imperial and 'mph' or 'km/h',drive=c.drive}
end
local function devices(v)
 local rt=runtime();return rt and rt.diffReports[v:getID()] or {}
end
local function requestFuel(v,operation)
 fuelOwner=tostring(v:getID())..':'..v:getJBeamFilename()
 fuelSerial=(fuelSerial or 0)+1;fuelRequest=tostring(fuelSerial)
 if operation then fuelOp={id=v:getID(),model=v:getJBeamFilename(),revision=tostring(data().vdata),run=operation,at=clock,token=fuelRequest} end
 v:queueLuaCommand('extensions.load("raceprepFuel") raceprepFuel.snapshot('..string.format('%q',fuelRequest)..')')
end
-- Rebuild only after a fresh VE energy snapshot. Never restore a stale tank
-- amount over another car, or silently refill while changing race parts.
local function rebuild(operation)
 local v=own();if not v then return reject('Choose your own car.') end
 if fuelOp or fuelRestore then return reject('Wait for the current setup change.') end
 if careerMode() then
  local ok,result,why=pcall(operation)
  if not ok or result==false then return reject(why or tostring(result)) end
  return true
 end
 requestFuel(v,operation);return true
end
M.onFuel=function(id,token,rows)
 local v=own();if not v or v:getID()~=id or token~=fuelRequest or type(rows)~='table' then return end
 fuelRows=rows;fuelSeen=clock
 local session=H.session();local racer=H.participant and H.participant();local rival=RivalsSession.view()
 local key=tostring(id)..':'..tostring(data().vdata)..':'..tostring(session and session.id or rival.id or 'free')
 local lap=session and session.state=='RACE' and racer and #(racer.lapTimes or {}) or rival.active and rival.completedLaps or nil
 local remaining=session and session.settings and tonumber(session.settings.laps) and racer and math.max(0,session.settings.laps-(racer.currentLap or 1)+1) or nil
 Strategy.sample(rows,key,lap,remaining,clock)
 local op=fuelOp
 if not op or op.token~=token then return end
 fuelOp=nil
 if op.id~=id or op.revision~=tostring(data().vdata) then return end
 local values={};for _,row in ipairs(rows) do values[row.name]={energy=fuelTargets[row.name] and row.maxEnergy*fuelTargets[row.name]/100 or row.energy,capacity=row.maxEnergy} end
 local ok,result,why=pcall(op.run)
 if not ok or result==false then return reject(why or tostring(result)) end
 fuelRestore={id=id,model=op.model,values=values,revision=op.revision,at=clock,expires=clock+8,token='restore:'..token}
 cachedData=nil
end
M.onFuelRestored=function(id,token)
 local v=own()
 if v and v:getID()==id and fuelRestore and fuelRestore.sent and fuelRestore.token==token then
  fuelRestore=nil;fuelSeen=nil;nextFuel=clock+.25
 end
end
local function fuelTick()
 local d,v=data();if not v or not d then return end
 local owner=tostring(v:getID())..':'..v:getJBeamFilename()
 if fuelOwner~=owner then fuelOwner=owner;fuelRows={};fuelTargets={};fuelRequest=nil;fuelSeen=nil end
 if fuelOp and clock-fuelOp.at>4 then fuelOp=nil;reject('Fuel snapshot timed out; car was not rebuilt. Retry Apply.') end
 if fuelRestore then
  local r=fuelRestore
  if v:getJBeamFilename()~=r.model or v:getID()~=r.id then fuelRestore=nil
  elseif clock>r.expires then fuelRestore=nil;reject('Fuel restoration was not confirmed; check fuel before Ready.')
  elseif not r.sent and tostring(d.vdata)~=r.revision then
   r.sent=true
   v:queueLuaCommand('extensions.load("raceprepFuel") raceprepFuel.apply('..serialize(r.values)..','..string.format('%q',r.token)..')')
  end
 end
 if fuelReapplyAt and clock>=fuelReapplyAt and not fuelOp and not fuelRestore then
  fuelReapplyAt=nil
  -- percent of each tank's own capacity, so no fresh tank reading is needed
  v:queueLuaCommand('extensions.load("raceprepFuel") raceprepFuel.applyPercent('..serialize(fuelTargets)..')');nextFuel=clock+.5
 end
 if not fuelOp and not fuelRestore and clock>=nextFuel and (M.visible or not fuelSeen or (H.session() and H.session().state=='RACE') or RivalsSession.active()) then nextFuel=clock+1;requestFuel(v) end
end
-- BJR's race-start teleport (setPosRot/safeTeleport) resets the car, and a
-- reset refills every tank. Re-apply the chosen fuel levels after a reset on
-- the grid or in the countdown only; a reset during the race keeps the game's
-- (and BJR's) own rule.
M.onVehicleResetted=function(id)
 RivalsSession.resetLap(id);Strategy.reset()
 local gaps=package.loaded['ge/extensions/raceprep/bjr/raceGaps'];if gaps then gaps.reset() end
 local v=own();if not v or v:getID()~=id or not next(fuelTargets) then return end
 local s=H.session and H.session()
 if type(s)=='table' and (s.state=='GRID' or s.state=='COUNTDOWN') then fuelReapplyAt=clock+.3 end
end

M.readyProblem=function()
 local v=own();if not H.ready() then return 'Waiting for BJR.' end
 if careerMode() then
  if not v then return 'Choose your own car first.' end
  if pending.tune or pending.diff then return 'Apply or discard your setup/differential changes.' end
  if pending.upgrades then return 'Apply or discard your upgrade changes.' end
  if fuelOp or fuelRestore then return 'Applying setup and restoring fuel.' end
  return nil
 end
 if not runtime() or not runtime().isServerManaged() then return 'Waiting for Motorsport Expansion server rules.' end
 if clock-hostSeen>5 then return "Waiting for the BeamJoy-Revived plugin API (BJR 2.0 or newer, started with the server)." end
 if not v then return 'Choose your own car first.' end
 local d=data();if not d then return 'Waiting for car data.' end
 if draftRevision and draftRevision~=tostring(d.vdata) then pending={tune=false,diff=false,upgrades=false};draftPreviewChanges={};draftChoices={};draftRevision=nil end
 if pending.tune or pending.diff then return 'Apply or discard your setup/differential changes.' end
 if pending.upgrades then return 'Apply or discard your upgrade changes.' end
 if fuelOp or fuelRestore then return 'Applying setup and restoring fuel.' end
 local setupProblem=Setup.specProblem(d,rules()) or Setup.aeroProblem(d,rules()) or Setup.diffProblem(d,rules(),runtime().diffSettings[v:getID()],devices(v)) or
  bodyAdapter(d).problem(d,U.catalog) or Setup.hiddenProblem(d)
 if setupProblem then return setupProblem end
 local r=rules();local e,why=rating(v)
 if not e then return why or 'Waiting for the car rating.' end
 if r.specModel and r.specModel~='' and v:getJBeamFilename()~=r.specModel then return 'This series requires '..r.specModel..'.' end
 if r.specConfig and r.specConfig~='' and e.config~=r.specConfig then return 'This series requires configuration '..r.specConfig..'.' end
 local classWhy=ClassBuild.refusal(r,e,raceprepRatings and raceprepRatings.factoryRating and raceprepRatings.factoryRating(v:getID()),require('ge/extensions/raceprep/rating').classOf);if classWhy then return classWhy end
 if r.allowedClasses and r.allowedClasses[e.class]==false then return 'Class '..e.class..' is not allowed.' end
 if tonumber(r.piMin) and e.pi<r.piMin then return 'PI is below the race minimum.' end
 if tonumber(r.piMax) and e.pi>r.piMax then return 'PI is above the race maximum.' end
 local short=require('ge/extensions/raceprep/partsRules').violation(v:getID(),r)
 if short then return short end
 local compound=U.compoundViolation(v:getID(),r);if compound then return compound end
 local capped=U.ruleFacts and UR.violation(r,U.ruleFacts(v:getID()));if capped then return capped end

end
local function guarded(original)
 return function(state,...)
  if state~=false then local why=M.readyProblem();if why then return reject(why) end end
  return original(state,...)
 end
end
local function hookReady()
 local runner=beamjoy_raceRunner
 if not runner or type(runner.ready)~='function' then restoreReady();return end
 if not readyHook or readyHook.runner~=runner or runner.ready~=readyHook.wrapper then
  restoreReady()
  local original=runner.ready;local wrapper=guarded(original)
  runner.ready=wrapper;readyHook={runner=runner,original=original,wrapper=wrapper}
 end
 for _,row in pairs(beamjoy_communications_ui and beamjoy_communications_ui.handlers or {}) do
  if row.key=='BJRaceReady' and type(row.callback)=='function' then
   local owned=false
   for _,b in ipairs(uiBindings) do if b.row==row and row.callback==b.wrapper then owned=true end end
   if not owned then
    local original=row.callback;local wrapper=guarded(original)
    uiBindings[#uiBindings+1]={row=row,original=original,wrapper=wrapper};row.callback=wrapper
   end
  end
 end
end
local function vehicleBadges()
 -- BJR's player list: each car's own class/PI (its label is per model)
 local out={}
 if not (raceprepRatings and raceprepRatings.getServerVehicle) then return out end
 for _,p in pairs(beamjoy_players and beamjoy_players.players or {}) do
  for _,veh in pairs(type(p.vehicles)=='table' and p.vehicles or {}) do
   if p.playerID and veh.vid then
    local sid=tostring(p.playerID)..'-'..tostring(veh.vid)
    local ok,e=pcall(raceprepRatings.getServerVehicle,sid)
    out[sid]=ok and e and e.class and e.pi and (e.class..' '..e.pi) or ''
   end
  end
 end
 return out
end
M.snapshot=function()
 local career=careerMode()
 local d,v=data();local r=runtime()
 local level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()
 if not M.visible then
  local out={autoRating=autoWorker and autoWorker.view() or {},level=level,ruleStore=r and r.rules,ruleDefaults=r and r.DEFAULT_RULES,rulesStatus=r and r.rulesStatus,
   ready=H.ready(),visible=false,frontend=career and 'ascension' or nil,railPage=M.railPage==true,openRequest=M.openRequest,openFull=M.openFull==true,resultNotice=resultNotice,
   draftReset=M.draftReset or 0,version=versionInfo.version or 'dev',tab=M.tab,vehicleBadges=vehicleBadges()}
  if v and d then
   local e,why=rating(v)
   out.car={id=v:getID(),model=v:getJBeamFilename(),rating=e,ratingStatus=why,revision=tostring(d.vdata)}
  end
  return out
 end
 local s=H.session()
 local director=require('ge/extensions/raceprep/director')
 local practice=require('ge/extensions/raceprep/session')
 local line=require('ge/extensions/raceprep/rubberLine')
 local raceList={};for _,race in pairs(beamjoy_races and beamjoy_races.data or {}) do raceList[#raceList+1]={id=race.id,name=race.name} end
 table.sort(raceList,function(a,b) return a.name<b.name end)
 local out={autoRating=autoWorker and autoWorker.view() or {},level=level,ruleStore=r and r.rules,ruleDefaults=r and r.DEFAULT_RULES,results=M.results,message=M.message,ready=H.ready(),visible=M.visible,frontend=career and 'ascension' or nil,railPage=M.railPage==true,openRequest=M.openRequest,openFull=M.openFull==true,vehicleBadges=vehicleBadges(),environment=(function() local ok,e=pcall(require('ge/extensions/raceprep/raceEnvironment').live);return ok and e or nil end)(),version=versionInfo.version or 'dev',tab=M.tab,canEdit=can('rules'),rules=rules(),
  abilities={weekend=can('weekend'),rules=can('rules'),raceControl=can('raceControl'),manageCrews=can('manageCrews')},motorsport=r and r.motorsport,
  weekend=practice.weekend(),announcement=practice.currentAnnouncement(),playerID=H.playerID(),
  -- the race whose rules lock upgrades now (lobby, or the running weekend)
  ruleScopeName=(function()
   if not ruleScope() then return nil end
   local race=H.race();if race then return race.name end
   local w=practice.weekend();return w and w.raceName or nil
  end)(),
  serverManaged=career or (r and r.isServerManaged()),serverBridgeReady=career or clock-hostSeen<=5,rulesStatus=r and r.rulesStatus,error=lastError,
  autoRating=autoWorker and autoWorker.view() or {},strategy=Strategy.view(),rivals=RivalsSession.view(),session=s,grid=Grid.snapshot(s,H.playerID(),raceprepRatings),diffApplied=M.diffApplied or 0,draftReset=M.draftReset or 0,resultNotice=resultNotice,pending=pending,applying=fuelOp~=nil or fuelRestore~=nil,practice=practice.data,myLaps=practice.laps,lastLap=practice.lastLap,
  sessionTiming=practice.status(),practiceActive=practice.active(),currentLapTime=practice.currentLapTime(),sessionRemaining=practice.remaining(),races=raceList,
  control=director.data,adminStatus=director.adminStatus,lights=director.lights,yellow=director.yellow(),falseStart=director.falseStart,
  driverRatings=(function()
   local out={}
   for _,p in pairs(director.data and director.data.driverStats or {}) do
    local id=tonumber(p.playerID)
    if id and raceprepRatings and raceprepRatings.getPlayer then
     local ok,e=pcall(raceprepRatings.getPlayer,id)
     if ok and type(e)=='table' and tonumber(e.pi) then
      local r={};for _,key in ipairs(Grid.RATING_FIELDS) do r[key]=e[key] end
      out[tostring(id)]=r
     end
    end
   end
   return out
  end)(),
  kts=M.kts,trackTemp=r and r.trackTemp,skills=r and r.skills,readyProblem=M.readyProblem(),editable=H.editable(),partsEditable=H.partsEditable(),tuningEditable=H.tuningEditable(),
  rubber=line.statusText(),rubberPeakPercent=math.floor(math.max(0,math.min(1,(line.peak or 0)/math.max(1,line.FULL or 1)))*100+.5),
  marbles=require('ge/extensions/raceprep/rubberMarbles').count(),
  weather=require('ge/extensions/raceprep/weather').status}
 if v and d then
  local e,why=rating(v);out.car={id=v:getID(),model=v:getJBeamFilename(),rating=e,ratingStatus=why,summary=U.summary(v:getID()),revision=tostring(d.vdata)}
  if M.visible then
   out.sharedTunes=sharedTunesView.model==v:getJBeamFilename() and sharedTunesView or {items={}}
   out.setupLibrary=library().list(v:getJBeamFilename(),Library.signature(d.vdata.activeParts or d.config.partsTree),Setup.mergeVars(d,{}))
   local curves=U.engineCurves and U.engineCurves(v:getID())
   local cacheKey=tostring(d.vdata)..':'..tostring(curves~=nil)
   if cachedData~=cacheKey then cachedData=cacheKey;cachedRows=U.list(v:getID()) end
   out.parts=cachedRows;out.variables=tuning(d);
   if ruleScope() then
    -- race-rule locks on a copy (cachedRows is shared until the car changes)
    local rows={}
    for i,row in ipairs(cachedRows) do
     local copy={};for k,val in pairs(row) do copy[k]=val end
     copy.options={}
     for j,o in ipairs(row.options or {}) do
      local oc={};for k,val in pairs(o) do oc[k]=val end
      oc.ruleBlock=ruleBlock(o.rule,row.current or '',o.name);copy.options[j]=oc
     end
     rows[i]=copy
    end
    out.parts=rows
   end
   out.piPreviewEnabled=M.piPreviewEnabled==true;out.targetClass=rules().targetClass
   if out.targetClass and out.targetClass~=''and e then
    local _,cap=ClassBuild.band(out.targetClass,require('ge/extensions/raceprep/rating').classOf);out.classOver=math.max(0,e.pi-cap)
   end
   -- PI options are lookup-only. Until the loading worker has persisted the
   -- matching per-part delta, report an explicit miss and never compile here.
   out.piEstimate={error='Not rated yet',before=e};out.optionEstimates={}

   out.conversionAvailability=require('ge/extensions/raceprep/engineConversions').view(v:getJBeamFilename())
   out.drivetrainAvailability=require('ge/extensions/raceprep/drivetrainConversions').view(v:getJBeamFilename())
   out.moreEngineSlots=false
   local engineInfo=U.engineInfo and U.engineInfo(v:getJBeamFilename(),d.vdata.activeParts)
   for _,row in ipairs(cachedRows) do
    if engineInfo and row.slot==(engineInfo.hubSlot or 'camso_tuning_parameters_engine') and (row.current or '')=='' then
     for _,option in ipairs(row.options or {}) do if option.name==engineInfo.hub then out.moreEngineSlots=true end end
    end
   end
   local locked=not H.editable() and 'Unready on the grid before editing; setup is locked during the race.' or
    not H.tuningEditable() and 'This BJR race uses a fixed tune; independent fuel changes may still be allowed.' or nil
   out.setupHints={tuning=rules().tuning==false and 'Tuning changes are disabled for this race.' or locked,
    aero=rules().aero==false and 'Aero changes are disabled; stock aero is required.' or locked,
    fuel=rules().fuel==false and 'Fuel changes are disabled for this race.' or not H.editable() and 'Fuel is locked while Ready or racing.' or nil}
   out.tyres=U.fittedTyres(v:getID())
   out.fuelTanks=fuelRows;out.fuelEditable=H.editable() and rules().fuel~=false
   out.engineCurves=curves and {stock=curves.stock,current=curves.current,limit=curves.limit}
   out.gearing=gearing(v)
   if raceprepRatings and raceprepRatings.getStats then
    local now,prev=raceprepRatings.getStats(v:getID())
    out.performance=now and {now=now,prev=prev,imperial=rawget(_G,'settings') and settings.getValue and settings.getValue('uiUnitLength')=='imperial' or false}
   end
   local carData=rawget(_G,'raceprepRatings') and raceprepRatings.getCarData and raceprepRatings.getCarData(v:getID())
   out.bodyStages=bodyAdapter(d).rows(d,U.catalog,type(carData)=='table' and carData.mass or nil)
   for _,st in ipairs(out.bodyStages or {}) do
    if st.key~='stock' and not st.fitted then st.blocked=ruleBlock({kind='body',stage=st.key},nil,true) end
   end
   local _,hidden=Setup.hiddenChanges(d);out.hiddenChanged=hidden
   out.enginePackages={}
   if U.engineInfo and U.engineInfo(v:getJBeamFilename(),d.vdata.activeParts) then
    for n=0,3 do
     local fitted=U.packageFitted(v:getID(),n)
     out.enginePackages[#out.enginePackages+1]={number=n,title=U.packageEffect(v:getID(),n),fitted=fitted,
      blocked=n>0 and not fitted and ruleBlock({kind='engine',rank=n},nil,true) or nil}
    end
   end
   out.tyreControls={}
   local catalogue=U.catalog or {}
   for _,axle in ipairs({'front','rear'}) do
    local stock=U.tyreStock and U.tyreStock(v:getID(),axle) or (catalogue.stocks or {})[v:getJBeamFilename()..'/'..axle]
    if stock and out.tyres and out.tyres[axle] then
     local fitted=(catalogue.parts or {})[out.tyres[axle].part]
     local compounds={}
     for _,c in ipairs(U.COMPOUNDS) do
      local slick=U.slickOf(c=='stock' and stock.compound or c)
      compounds[#compounds+1]={value=c,label=c=='stock' and ('Stock ('..(U.COMPOUND_LABELS[stock.compound] or stock.compound)..')') or U.COMPOUND_LABELS[c],allowed=not H.onGrid() or U.slickAllowed(rules(),slick),
       blocked=ruleBlock({kind='tyre',compound=c=='stock' and stock.compound or c,offset=0},fitted and fitted.compound or 'stock',c)}
     end
     local widthBlocked={}
     for _,w in ipairs({-20,0,20,40}) do
      widthBlocked[tostring(w)]=ruleBlock({kind='tyre',compound='standard',offset=w},fitted and fitted.offsetMM or 0,w)
     end
     out.tyreControls[#out.tyreControls+1]={axle=axle,widthMM=stock.widthMM,compound=fitted and fitted.compound or 'stock',offset=fitted and fitted.offsetMM or 0,compounds=compounds,widthBlocked=widthBlocked}
    end
   end
   out.differentials={}
   for _,dev in ipairs(devices(v)) do
    local row={};for k,val in pairs(dev) do row[k]=val end
    local setting=(r.diffSettings[v:getID()] or {})[dev.name]
    if setting then for k,val in pairs(setting) do row[k]=val end;row.applied=setting.mode~='stock' or setting.split~=nil end
    row.frontShare=row.split and Setup.front(dev,row.split)
    local racePart=P.raceDifferential(d.vdata,dev.position)
    row.canEdit=H.tuningEditable() and rules().diff~=false and racePart==true
    row.reason=rules().diff==false and 'Differential changes are disabled for this race.' or
     not H.tuningEditable() and 'Unready before editing; the BJR session or fixed tune locks this differential.' or
     not racePart and 'Fit a race differential on this axle to unlock its controls.' or nil
    row.canSplit=row.canEdit and rules().centreSplit~=false
    if dev.position=='centre' then
     local m=(d.vdata.variables or {})['$torquesplit'];local value=m and ((d.config.vars or {})['$torquesplit'] or m.val or m.default)
     if value then row.frontShare=Setup.front(dev,value);row.reload=true end
    end
    out.differentials[#out.differentials+1]=row
   end
   out.aids=r and r.aids[v:getID()]
   -- the last change belongs to one car: a replaced vehicle can keep its id,
   -- so the model is pinned at first sight too ("was S 796" on the next car)
   local lc,model=U.lastChange,v:getJBeamFilename()
   if lc and lc.vehID==v:getID() and lc.model==nil then lc.model=model end
   out.lastUpgrade=lc and lc.vehID==v:getID() and lc.model==model and lc or nil
  end
 end
 return out
end
-- The native selector asks this public BJR hook for every pickable tile.
M.onBJRequestCanSpawnVehicle=function(req,model,config,action)
 if H.onGrid() then Selector.authorize(req,model,config,rules(),raceprepRatings) end
end
local selectorStamp,selectorBinding
if Selector==nil then Selector=mpModule('ge/extensions/raceprep/bjr/selector',stubSelector) end
local function refreshSelector()
 if ui_vehicleSelector_general and (not selectorBinding or selectorBinding.mod~=ui_vehicleSelector_general or ui_vehicleSelector_general.passesFilters~=selectorBinding.wrapper) then
  Selector.restore(selectorBinding)
  selectorBinding=Selector.wrap(ui_vehicleSelector_general,H.onGrid,rules,function() return raceprepRatings end,function(model) return core_vehicles and core_vehicles.getModel(model) end)
 end
 local r=runtime()
 local stamp=tostring(H.session() and H.session().id)..tostring(r and r.rules)..tostring(raceprepRatings and raceprepRatings.catalogRevision)
 if stamp~=selectorStamp then
  selectorStamp=stamp;Selector.reset()
  if ui_vehicleSelector_general and ui_vehicleSelector_general.clearCache then ui_vehicleSelector_general.clearCache() end
  if vehicleSelector and vehicleSelector.onBJVehiclesCacheUpdate then vehicleSelector.onBJVehiclesCacheUpdate() end
 end
end
local actions={}
actions.draft=function(p)
 local d=data();if not d or p.revision~=tostring(d.vdata) then return end
 draftRevision=p.revision
 if type(p.tune)=='boolean' then pending.tune=p.tune end
 if type(p.diff)=='boolean' then pending.diff=p.diff end
 if type(p.upgrades)=='boolean' then pending.upgrades=p.upgrades end
 if checkedDraft and p.parts then local changes=checkedDraft(p);if type(changes)=='table'then draftPreviewChanges=changes;draftChoices=p end end
end
actions.discard=function() draftPreviewChanges={};draftChoices={};pending={tune=false,diff=false,upgrades=false};M.draftReset=(M.draftReset or 0)+1 end
local historyAsked=-1e9
local historyCache
actions.history=function()
 local level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()
 if historyCache and historyCache.level==level then guihooks.trigger('RacePrepBJRHistory',historyCache) end
 if H.ready() and clock-historyAsked>=5 then historyAsked=clock;H.send('RacePrepGetHistory',{}) end
 return true
end
autoWorker=AutoRatingWorker.new{
 current=function() local v=H.vehicle();if not v then return end;if not v.getVelocity then return end;local velocity=v:getVelocity();return{id=v:getID(),speed=velocity:length()}end,
 free=function() return H.ready() and not H.session() and not RivalsSession.active() end,
 spawn=function(model,config)
  local current=H.vehicle();local pos=current and current:getPosition() or vec3(0,0,1)
  local v=core_vehicles.spawnNewVehicle(model,{config=config and ('vehicles/'..model..'/'..config:gsub('%.pc$','')..'.pc'),autoEnterVehicle=false,pos=pos+vec3(80,80,2),vehicleName='bjrme-rating-worker'})
  return v and v:getID()
 end,
 delete=function(id) local v=be:getObjectByID(id);if v then v:delete()end end,
 enter=function(id) local v=be:getObjectByID(id);if v then be:enterVehicle(0,v)end end,
 freeCamera=function() if commands and commands.setFreeCamera then commands.setFreeCamera()end end,
 rated=function(id) return raceprepRatings and raceprepRatings.getVehicle(id)~=nil end,
 send=function(p) if H.ready() then H.send('RacePrepAutoRating',p)end end,
}
actions.rateNow=function() H.send('RacePrepAutoRating',{action='rate'})end
actions.show=function(p) M.visible=p.value~=false;uiReady=true;nextPush=0;if M.visible then H.send('RacePrepGetChallenges',{});H.send('RacePrepGetPresets',{});H.send('RacePrepGetProgress',{}) elseif careerMode() and Career and Career.active() then Career.close() end end
actions.refresh=function() uiReady=true;cachedData=nil;drivingIdleSent=nil;diffVdata={};nextPush=0 end
actions.tab=function(p) if type(p.name)=='string' then M.tab=p.name:sub(1,30) end end
actions.openTuning=function()
 if not careerMode() then return false end
 if not Career then return false end
 local ok,err=Career.openTuning();if not ok then return reject(err) end;return true
end
actions.chooseCar=function()
 if not H.editable() then return reject('Unready before changing the car.') end
 if ui_vehicleSelector_general and ui_vehicleSelector_general.openFromPause then ui_vehicleSelector_general.openFromPause('pause.vehicleSelector')
 elseif ui_router and ui_router.navigate then ui_router.navigate('menu.vehicles')
 else guihooks.trigger('ChangeState',{state='menu.vehicles'}) end
end
actions.ready=function(p) if beamjoy_raceRunner then beamjoy_raceRunner.ready(p.value~=false) end end
actions.leave=function() if beamjoy_raceRunner then beamjoy_raceRunner.leave() end end
actions.part=function(p)
 if not H.partsEditable() then return reject('Parts are locked by this session or its BJR vehicle restriction.') end
 local d,v=data();if not d then return end
 local row=U.list(v:getID())[tonumber(p.index) or 0]
 if not row then return reject('Parts list changed; refresh it.') end
 local allowed,reason=U.allowed(row.group,rules(),not H.session(),H.onGrid())
 if not allowed then return reject(reason) end
 local found=false;for _,o in ipairs(row.options or {}) do if o.name==p.name then found=true end end
 if not found then return reject('That part is not compatible with this slot.') end
 return rebuild(function() return U.apply(v:getID(),row,p.name,rating(v)) end)
end
actions.undo=function() local v=own();if v and H.partsEditable() then return rebuild(function() return U.undo(v:getID()) end) end end
actions.saveSetup=function(p)
 if type(p.name)~='string' or not p.name:match('^[%w _%-]+$') or #p.name>80 then return reject('Use a setup name with letters, numbers, spaces or dashes.') end
 local ok,msg=U.save(p.name);if not ok then return reject(msg) end;M.message=msg;return true
end
actions.rivalsStart=function(p)
 if not H.ready() or clock-hostSeen>5 then return reject('Waiting for the Motorsport Expansion server bridge.') end
 if H.session() or require('ge/extensions/raceprep/session').active() then return reject('Return to free roam and end the current practice activity first.') end
 local v=own();if not v then return reject('Choose your own rated car.') end
 local mp=MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(v:getID())
 local sid=mp and (mp.serverVehicleID or mp.serverVehicleString)
 if not sid then return reject('Waiting for the network car identity.') end
 H.send('RacePrepRivals',{action='start',rotation=p.rotation,weekly=p.weekly==true,practice=p.practice==true,challenge=p.challenge,runID=p.runID,competitor=p.competitor,model=p.model,vehicle=sid})
end
actions.challenges=function(p) H.send('RacePrepGetChallenges',p or {}) end
actions.rivalsModerate=function(p) H.send('RacePrepRivalsModerate',p) end
actions.rivalsStop=function() RivalsSession.stop() end
actions.rivalsGhosts=function(p) RivalsSession.setGhosts(p) end
actions.rivalsGoToStart=function() local ok,why=RivalsSession.goToStart();if not ok then return reject(why) end;return true end
actions.radar=function(p)
 radarEnabled=p.enabled==true
 if radarEnabled and extensions and extensions.load and not ui_vehicleRadarApp then extensions.load('ui_vehicleRadarApp') end
end
actions.sharedTunes=function(p)
 local d,v=data();if not d or not v then return reject('Choose your own car.') end
 local mp=MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(v:getID())
 local sid=mp and (mp.serverVehicleID or mp.serverVehicleString)
 local payload={action=p.action,id=p.id,vehicle=sid,model=v:getJBeamFilename(),hardware=Library.signature(d.vdata.activeParts or d.config.partsTree)}
 if p.action=='publish' then
  local e=library().get(p.id)
  if not e or e.model~=payload.model or e.hardware~=payload.hardware then return reject('Fit the same car and hardware before publishing this tune.') end
  payload.entry=e;payload.notes=p.notes
 end
 sharedTunePending=p.action
 H.send('RacePrepSharedTunes',payload)
end
actions.librarySave=function(p)
 local d,v=data();if not v or not d then return reject('Choose your own car.') end
 if pending.tune or pending.diff or pending.upgrades or fuelOp or fuelRestore then return reject('Apply or discard pending edits before saving the applied setup.') end
 local e=rating(v) or {};local rt=runtime()
 local ok,msg=library().save(p.name,{model=v:getJBeamFilename(),hardware=Library.signature(d.vdata.activeParts or d.config.partsTree),
  vars=Setup.mergeVars(d,{}),diffs=rt and rt.diffSettings and rt.diffSettings[v:getID()] or {},pi=e.pi,class=e.class})
 if not ok then return reject(msg) end;M.message=msg;return true
end
actions.libraryChange=function(p)
 if fuelOp or fuelRestore then return reject('Wait for the current setup change.') end
 local ok,msg=library().change(p.action,p.id,p.name)
 if not ok then return reject(msg) end;M.message=msg;return true
end
actions.libraryLoad=function(p)
 local d,v=data();local rt=runtime();local entry=library().get(p.id)
 if not v or not d or not rt or not H.tuningEditable() then return reject('Setup loading is locked; unready or return to free roam.') end
 if pending.tune or pending.diff or pending.upgrades then return reject('Apply or discard pending edits before loading a setup.') end
 if not entry or entry.model~=v:getJBeamFilename() or entry.hardware~=Library.signature(d.vdata.activeParts or d.config.partsTree) then return reject('This setup requires the same car and fitted parts.') end
 local checkedRules=Library.signature(rules())
 local meta={};for _,m in ipairs(tuning(d)) do meta[m.name]=m end
 local current=Setup.mergeVars(d,{});local target={}
 for key,value in pairs(entry.vars or {}) do
  if current[key]~=value then
   local m=meta[key];local n=Setup.finite(value)
   if not m or not m.allowed or not n or n<m.min or n>m.max then return reject('Saved setting is unavailable, out of range or locked: '..tostring(key)) end
   target[key]=n
  end
 end
 local invalidDiff=Setup.diffProblem({vdata=d.vdata,config={vars=Setup.mergeVars(d,target)}},rules(),entry.diffs or {},devices(v))
 if invalidDiff then return reject(invalidDiff) end
 local diffs,diffVars,why=Setup.diffApply(d,rules(),devices(v),entry.diffs or {})
 if not diffs then return reject(why) end
 for key,value in pairs(diffVars) do target[key]=value end
 local prospective={vdata=d.vdata,config={vars=Setup.mergeVars(d,target)}}
 why=Setup.diffProblem(prospective,rules(),diffs,devices(v)) or Setup.aeroProblem(prospective,rules()) or
  require('ge/extensions/raceprep/partsRules').violation(v:getID(),rules()) or U.compoundViolation(v:getID(),rules())
 if why then return reject(why) end
 return rebuild(function()
  if not H.tuningEditable() or Library.signature(rules())~=checkedRules or own()~=v or Library.signature(data().vdata.activeParts or data().config.partsTree)~=entry.hardware then return false,'Car or session changed; setup was not loaded.' end
  -- Undo and fuel restoration use the same path as workshop changes.
  U.history[#U.history+1]={vehID=v:getID(),tree=deepcopy(d.config.partsTree),vars=deepcopy(d.config.vars or {}),diffs=deepcopy(rt.diffSettings[v:getID()] or {}),label='Load setup: '..entry.name}
  while #U.history>20 do table.remove(U.history,1) end
  rt.applyDiff(v:getID(),diffs)
  core_vehicle_partmgmt.setConfigVars(Setup.mergeVars(d,target),true)
  M.diffApplied=(M.diffApplied or 0)+1;M.draftReset=(M.draftReset or 0)+1;M.message='Loaded '..entry.name..'.';return true
 end)
end
actions.enginePackage=function(p)
 local v=own();local n=tonumber(p.number)
 if not v or not H.partsEditable() then return reject('Engine parts are locked.') end
 local allowed,why=U.allowed('engine',rules(),not H.session(),H.onGrid())
 if not allowed then return reject(why) end
 if not n or n%1~=0 or n<0 or n>3 then return reject('Unknown engine package.') end
 if n>0 then local blocked=ruleBlock({kind='engine',rank=n},nil,true);if blocked then return reject(blocked) end end
 return rebuild(function() return U.applyPackage(v:getID(),n,rating(v)) end)
end
actions.bodyStage=function(p)
 local v=own();if not v or not H.partsEditable() then return reject('Body parts are locked.') end
 local allowed,why=U.allowed('body',rules(),not H.session(),H.onGrid());if not allowed then return reject(why) end
 if type(p.key)~='string' or not bodyAdapter(data()).find(p.key) then return reject('Unknown body stage.') end
 if p.key~='stock' then local blocked=ruleBlock({kind='body',stage=p.key},nil,true);if blocked then return reject(blocked) end end
 return rebuild(function() return U.applyWeight(v:getID(),p.key,rating(v)) end)
end
-- settings changed in BeamNG's tuning menu that racing requires at default
actions.resetHidden=function()
 local d,v=data();if not v or not H.editable() then return reject('Unready before changing setup.') end
 local changes=Setup.hiddenChanges(d);if not changes then return true end
 return rebuild(function() core_vehicle_partmgmt.setConfigVars(Setup.mergeVars(d,changes),true);return true end)
end
actions.engineSlots=function()
 local d,v=data();if not v or not H.partsEditable() then return reject('Engine parts are locked.') end
 local allowed,why=U.allowed('engine',rules(),not H.session(),H.onGrid());if not allowed then return reject(why) end
 local info=U.engineInfo and U.engineInfo(v:getJBeamFilename(),d.vdata.activeParts)
 if not info then return reject('No compatible extra engine slots for this car.') end
 for _,row in ipairs(U.list(v:getID())) do
  if row.slot==(info.hubSlot or 'camso_tuning_parameters_engine') and (row.current or '')=='' then
   for _,option in ipairs(row.options or {}) do
    if option.name==info.hub then return rebuild(function() return U.apply(v:getID(),row,info.hub,rating(v)) end) end
   end
  end
 end
 return reject('Extra engine slots are already fitted or unavailable.')
end
-- Tyre changes for one or both axles: {{axle,compound,offset}...} -> parts
-- changes. One slick compound per car (KTS): a slick on one axle needs the
-- same slick on the other, taken from the request or mirrored onto the fitted
-- tyre. Returns changes or nil, why.
local function tyreChanges(v,specs)
 local model=v:getJBeamFilename();local stocks=U.catalog.stocks;local rows={}
 for _,row in ipairs(U.list(v:getID())) do
  rows[row.slot]=row
  if row.nativeTyre then
   if stocks==U.catalog.stocks then stocks={} end
   stocks[model..'/'..row.axle]=row.nativeStock
   rows['Camso_wheels_'..row.axle]=row -- lookup alias; row.path keeps native slots
  end
 end
 local function select(axle,compound,width)
  local stock=stocks[model..'/'..axle];local row=rows['Camso_wheels_'..axle]
  if not stock or not row then return end
  if H.onGrid() and not U.slickAllowed(rules(),U.slickOf(compound=='stock' and stock.compound or compound)) then return end
  local name=compound=='stock' and width==0 and stock.part
  local pool=(U.catalog.byModel and U.catalog.byModel[model]) or U.catalog.parts
  if not name then for key,part in pairs(pool) do
   if part.kind=='tyre' and part.model==model and part.stockPart==stock.part and part.compound==compound and part.offsetMM==width then name=key;break end
  end end
  if name then return {row,name} end
 end
 local wanted,changes={},{}
 for _,t in ipairs(specs) do
  if t.axle~='front' and t.axle~='rear' then return nil,'Unknown axle.' end
  local offset=tonumber(t.offset);if offset~=-20 and offset~=0 and offset~=20 and offset~=40 then return nil,'Unknown tyre width.' end
  local valid=false;for _,c in ipairs(U.COMPOUNDS) do if c==t.compound then valid=true end end
  if not valid then return nil,'Unknown tyre compound.' end
  local stock=stocks[model..'/'..t.axle]
  local change=select(t.axle,t.compound,offset);if not change or not stock then return nil,'Tyre combination unavailable or banned by race rules.' end
  local fittedNow=(U.fittedTyres(v:getID()) or {})[t.axle]
  local wantCompound=t.compound=='stock' and stock.compound or t.compound
  local blocked=ruleBlock({kind='tyre',compound=wantCompound,offset=offset},
   fittedNow and (tostring(fittedNow.compound)..':'..tostring(fittedNow.offsetMM or 0)),wantCompound..':'..tostring(offset))
  if blocked then return nil,blocked end
  wanted[t.axle]={compound=t.compound,offset=offset,slick=U.slickOf(t.compound=='stock' and stock.compound or t.compound)}
  changes[#changes+1]=change
 end
 local fitted=U.fittedTyres(v:getID())
 for axle,w in pairs(wanted) do
  local other=axle=='front' and 'rear' or 'front'
  if w.slick then
   if wanted[other] then
    if wanted[other].slick and wanted[other].slick~=w.slick then return nil,'Both axles need the same slick compound.' end
   elseif fitted and fitted[other] and (fitted[other].unknownSlickGrade or (U.slickOf(fitted[other].compound) and U.slickOf(fitted[other].compound)~=w.slick)) then
    local otherRow=rows['Camso_wheels_'..other];local info=otherRow and U.catalog.parts[otherRow.current]
    local mirror=select(other,'race_'..w.slick,info and info.offsetMM or 0)
    if not mirror then return nil,'Matching slick unavailable on the other axle.' end
    changes[#changes+1]=mirror
   end
  end
 end
 return changes
end
actions.tyre=function(p)
 local d,v=data();if not v or not H.partsEditable() then return reject('Tyre parts are locked.') end
 local allowed,why=U.allowed('tyres',rules(),not H.session(),H.onGrid());if not allowed then return reject(why) end
 local changes,err=tyreChanges(v,{p});if not changes then return reject(err) end
 local stock=U.tyreStock and U.tyreStock(v:getID(),p.axle) or U.catalog.stocks[v:getJBeamFilename()..'/'..p.axle]
 return rebuild(function() return U.applyMany(v:getID(),changes,p.axle..' tyres: '..p.compound..' '..(stock.widthMM+tonumber(p.offset))..' mm',rating(v)) end)
end
-- Upgrades > Apply upgrades: every pending part and tyre in one reload.
-- parts={{index,name}}, tyres={{axle,compound,offset}}
checkedDraft=function(p)
 local d,v=data();if not v or not H.partsEditable() then return reject('Parts are locked by this session or its BJR vehicle restriction.') end
 local changes,labels={},{}
 local list=U.list(v:getID())
 for _,c in ipairs(type(p.parts)=='table' and p.parts or {}) do
  -- by slot path: rows can shift while the car loads or a stage adds slots
  local row
  if type(c.path)=='string' then
   for _,r in ipairs(list) do if table.concat(r.path or {},'/')==c.path then row=r end end
  else row=list[tonumber(c.index) or 0] end
  if not row then return reject('Parts list changed; refresh it.') end
  local allowed,why=U.allowed(row.group,rules(),not H.session(),H.onGrid());if not allowed then return reject(why) end
  local option
  for _,o in ipairs(row.options or {}) do if o.name==c.name then option=o end end
  if not option then return reject('That part is not compatible with '..tostring(row.title)..'.') end
  if option.unsafe and c.name~=row.current then return reject(option.unsafe) end
  local blocked=ruleBlock(option.rule,row.current or '',c.name);if blocked then return reject(blocked) end
  if c.name~=row.current then changes[#changes+1]={row,c.name};labels[#labels+1]=tostring(row.title) end
 end
 local tyres=type(p.tyres)=='table' and p.tyres or {}
 if #tyres>0 then
  local allowed,why=U.allowed('tyres',rules(),not H.session(),H.onGrid());if not allowed then return reject(why) end
  local more,err=tyreChanges(v,tyres);if not more then return reject(err) end
  for _,c in ipairs(more) do changes[#changes+1]=c end
  labels[#labels+1]='tyres'
 end
 if p.body then
  local W=bodyAdapter(d);local stage=W.find(p.body);if not stage then return reject('Unknown weight stage.')end
  local allowed,why=U.allowed('body',rules(),not H.session(),H.onGrid());if not allowed then return reject(why)end
  local blocked=ruleBlock({kind='body',stage=p.body},W.stage(d,U.catalog).key,p.body);if blocked then return reject(blocked)end
  changes[#changes+1]={{title='Weight reduction',group='body',bodyStage=true,path={'@body'}},p.body};labels[#labels+1]='Weight reduction'
 end
 return changes,labels,d,v
end
actions.upgrades=function(p)
 local changes,labels,d,v=checkedDraft(p);if type(changes)~='table'then return false end
 if #changes==0 then return reject('No upgrade changes to apply.') end
 for _,c in ipairs(changes) do
  if c[1].group=='conversion' and #changes~=1 then return reject('Apply the engine conversion separately, then choose its upgrades.') end
 end
 pending.upgrades=false;draftPreviewChanges={};draftChoices={}
 if Career then return rebuild(function() return Career.applyChanges(v:getID(),changes,'Upgrades: '..table.concat(labels,', ')) end) end
 return rebuild(function() return U.applyMany(v:getID(),changes,'Upgrades: '..table.concat(labels,', '),rating(v)) end)
end
actions.classPreset=function(p)
 M.preparedPreset=nil;M.preparedRules=nil
 for _,item in ipairs(M.presetLibrary and M.presetLibrary.items or {})do if item.id==p.id and item.offered and item.patch and item.patch.targetClass and item.patch.targetClass~=''then
  local base=deepcopy(runtime()and runtime().DEFAULT_RULES or {});local function merge(a,b)for k,v in pairs(b)do if type(v)=='table'then a[k]=type(a[k])=='table'and a[k]or{};merge(a[k],v)else a[k]=v end end end
  merge(base,item.patch);M.preparedRules=base;M.preparedPreset=item.id
 end end
 nextPush=0
end
actions.piPreview=function(p) M.piPreviewEnabled=p.enabled==true end
actions.quickClass=function()
 M.message='Rating upgrades…';return reject('Rating upgrades are not available yet.')
end
actions.fuel=function(p)
 local v=own();if not v or not H.editable() or rules().fuel==false or fuelOp or fuelRestore then return reject('Fuel is locked.') end
 if not fuelSeen or clock-fuelSeen>3 then return reject('Waiting for a fresh tank reading.') end
 local percent=Setup.finite(p.percent);if not percent or percent<0 or percent>100 then return reject('Invalid tank level.') end
 for _,row in ipairs(fuelRows) do if row.name==p.name then
  fuelTargets[row.name]=percent;row.energy=row.maxEnergy*percent/100
  v:queueLuaCommand('extensions.load("raceprepFuel") raceprepFuel.apply('..serialize({[row.name]=row.energy})..')');return true
 end end
 return reject('Unknown energy tank.')
end
actions.tune=function(p)
 if not H.editable() then return reject('Unready before changing setup.') end
 local d=data();if not d or type(p.vars)~='table' then return false end
 local defs={};for _,m in ipairs(tuning(d)) do defs[m.name]=m end
 local values={}
 for name,value in pairs(p.vars) do
  local meta=defs[name];value=Setup.finite(value)
  if not meta or not meta.allowed or not value then return reject('Invalid or locked setup setting: '..tostring(name)) end
  values[name]=math.max(meta.min,math.min(meta.max,value))
 end
 local vars={};for k,val in pairs(d.config.vars or {}) do vars[k]=val end;for k,val in pairs(values) do vars[k]=val end
 local prospective={vdata=d.vdata,config={vars=vars}}
 local why=Setup.diffProblem(prospective,rules(),runtime().diffSettings[own():getID()],devices(own())) or Setup.aeroProblem(prospective,rules())
 if why then return reject(why) end
 return rebuild(function() core_vehicle_partmgmt.setConfigVars(Setup.mergeVars(d,values),true);pending.tune=false;return true end)
end
actions.aeroReset=function()
 if not H.tuningEditable() then return reject('Setup is locked.') end
 local d=data();local values={}
 for name,m in pairs(d.vdata.variables or {}) do if Setup.aero(name,m) and Setup.finite(m.default) then values[name]=m.default end end
 return rebuild(function() core_vehicle_partmgmt.setConfigVars(Setup.mergeVars(d,values),true);pending.tune=false;return true end)
end
actions.diff=function(p)
 local d,v=data();if not v or not H.tuningEditable() then return reject('Differentials are locked.') end
 if p.preset and not ({race=true,drift=true,stock=true})[p.preset] then return reject('Unknown differential preset.') end
 local requested=p.preset and Setup.preset(p.preset,devices(v)) or p.settings
 if p.preset and p.preset~='stock' then
  for _,dev in ipairs(devices(v)) do
   if not P.raceDifferential(d.vdata,dev.position) then requested[dev.name]=(runtime().diffSettings[v:getID()] or {})[dev.name] or {mode='stock'} end
  end
 end
 if type(requested)~='table' then return reject('Missing differential settings.') end
 local values,vars,why=Setup.diffApply(d,rules(),devices(v),requested)
 if not values then return reject(why) end
 local function apply()
  runtime().applyDiff(v:getID(),values);pending.diff=false;M.diffApplied=(M.diffApplied or 0)+1
  if next(vars) then core_vehicle_partmgmt.setConfigVars(Setup.mergeVars(d,vars),true) end
  return true
 end
 if next(vars) then return rebuild(apply) end
 return apply()
end

actions.rules=function(p)
 if not can('rules') then return reject('Your BeamJoy group cannot edit race rules.') end
 if clock-hostSeen>5 then return reject('Waiting for the BeamJoy-Revived plugin API (BJR 2.0 or newer, started with the server).') end
 local scope=tostring(p.scope or 'default')
 if scope~='default' then
  local found=false;for _,r in ipairs(beamjoy_races and beamjoy_races.data or {}) do if tostring(r.id)==scope then found=true end end
  if not found then return reject('Choose a race on the current map.') end
  scope=tostring(getCurrentLevelIdentifier())..':'..scope
 end
 runtime().sendRules(scope,p.rules)
end
actions.track=function(p)
 if not can('rules') then return reject('Your BeamJoy group cannot edit track settings.') end
 if clock-hostSeen>5 then return reject('Waiting for the BeamJoy-Revived plugin API (BJR 2.0 or newer, started with the server).') end
 local director=require('ge/extensions/raceprep/director')
 local track=director.data and director.data.track
 if not track or (getCurrentLevelIdentifier and track.level~=getCurrentLevelIdentifier()) then
  return reject('Waiting for server track settings for the current map.')
 end
 director.setTrack(p)
end
actions.weekendStart=function(p)
 if not can('weekend') then return reject('Your BeamJoy group cannot start a race weekend.') end
 local found=false;for _,r in pairs(beamjoy_races and beamjoy_races.data or {}) do if tostring(r.id)==tostring(p.raceID) then found=true end end
 if not found then return reject('Choose a race on the current map.') end
 require('ge/extensions/raceprep/session').weekendStart(p.raceID,tonumber(p.practiceMinutes),tonumber(p.qualifyingMinutes),p.gridOrder,tonumber(p.raceLaps))
end
actions.weekendNext=function() if can('weekend') then require('ge/extensions/raceprep/session').weekendNext() end end
actions.weekendEnd=function() if can('weekend') then require('ge/extensions/raceprep/session').weekendEnd() end end
-- Motorsport settings: {permissions, weekend}; the server checks the permission
actions.rivalNotice=function(p) H.send('RacePrepRivalNotices',p) end
actions.eventPresets=function(p) H.send('RacePrepPresetAction',p) end
actions.progression=function(p) H.send('RacePrepProgressAction',p) end
actions.progressCache=function() if M.challenges then guihooks.trigger('RacePrepBJRChallenges',M.challenges) end; H.send('RacePrepGetPresets',{});if M.presetLibrary then guihooks.trigger('RacePrepBJRPresets',M.presetLibrary) end;H.send('RacePrepGetProgress',{});if M.progress then guihooks.trigger('RacePrepBJRProgress',M.progress) end;if M.progressHistory then guihooks.trigger('RacePrepBJRLeague',M.progressHistory) end end
actions.motorsport=function(p)
 if not can('rules') and not (p.scope=='crews' and can('manageCrews')) then return reject('Your BeamJoy group cannot change Motorsport settings.') end
 if type(p.permissions)~='table' or type(p.weekend)~='table' then return reject('Invalid settings.') end
 H.send('RacePrepSetMotorsport',p)
end
-- Motorsport settings > Optional mods: stop reminders for one mod
actions.optionalIgnore=function(p)
 if not can('rules') then return reject('Your BeamJoy group cannot change Motorsport settings.') end
 if type(p.key)~='string' then return reject('Invalid mod.') end
 H.send('RacePrepOptionalIgnore',{key=p.key:sub(1,20)})
end
actions.goToTrack=function() return require('ge/extensions/raceprep/session').goToTrack() end
actions.yellow=function(p) if can('raceControl') then require('ge/extensions/raceprep/director').adminYellow(p.enabled==true) end end
actions.championship=function(p) if can('rules') then require('ge/extensions/raceprep/director').championship(p.action,p) end end
M.dispatch=function(request)
 if type(request)~='table' or not actions[request.action] then return false end
 lastError=nil
 local ok,result=pcall(actions[request.action],type(request.payload)=='table' and request.payload or {})
 if not ok then lastError=tostring(result);log('E','raceprepBJR',lastError) end
 nextPush=0;return ok and result~=false
end
M.onUpdate=function(dt)
 clock=clock+(dt or 0)
 careerMode()
 if not careerMode() then RatingStep.tick(dt or 0) end
 Sidebar.update()
 if not H.ready() then
  if wasReady then M.onServerLeave() end
  wasReady=false;return
 end
 wasReady=true
 if not handlerRegistered and (AddEventHandler or Frontend.isCareer()) then
  require('ge/extensions/raceprep/net').on('RacePrepRivalNotice',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then guihooks.trigger('RacePrepBJRRivalNotice',p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepRivalGhost',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then actions.rivalsStart(p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepAutoRatingJob',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table'then autoWorker.receive(p)end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepAutoRatingState',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table'then M.autoRatings=p;if raceprepRatings and raceprepRatings.autoRatings then raceprepRatings.autoRatings(p)end;guihooks.trigger('RacePrepBJRAutoRatings',p)end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepChallenges',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then M.challenges=p;guihooks.trigger('RacePrepBJRChallenges',p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepPresets',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then M.presetLibrary=p;if M.preparedPreset then actions.classPreset({id=M.preparedPreset})end;local rt=runtime();if rt then rt.presetSessions=p.sessions or {} end;guihooks.trigger('RacePrepBJRPresets',p);nextPush=0 end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepReward',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then guihooks.trigger('RacePrepBJRReward',p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepDriverCard',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then M.driverCard=p;guihooks.trigger('RacePrepBJRDriverCard',p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepLeague',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then M.progressHistory=p;guihooks.trigger('RacePrepBJRLeague',p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepProgress',function(wire) local ok,p=pcall(jsonDecode,wire);if ok and type(p)=='table' then M.progress=p;guihooks.trigger('RacePrepBJRProgress',p) end end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepBJRResults',M.onResults,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepSharedTunes',function(wire)
   local ok,p=pcall(jsonDecode,wire or '');if not ok or type(p)~='table' then return end
   if p.items then sharedTunesView=p;sharedTunePending=nil end
   if p.error then reject(p.error) end
   if p.message then
    M.message=p.message
    if sharedTunePending=='publish' then sharedTunePending=nil;actions.sharedTunes({action='list'}) end
   end
   if p.entry then
    local e=p.entry;e.sharedSource=e.id;e.id=nil
    local base=(e.name..' ('..tostring(e.author or 'shared')..')'):sub(1,72)
    local success,msg=library().save(base,e)
    if not success then reject(msg) else M.message='Copied to your local library: '..base end
    sharedTunePending=nil
   end
  end)
  require('ge/extensions/raceprep/net').on('RacePrepRivalsSession',function(wire)
   local ok,p=pcall(jsonDecode,wire or '');if not ok or type(p)~='table' then return end
   RivalsSession.receive(p)
   if p.track and RivalsSession.active() then
    local why=M.readyProblem();if why then RivalsSession.stop();reject('Rivals build does not meet the selected rules: '..why) end
   end
  end)
  require('ge/extensions/raceprep/net').on('RacePrepHistory',function(wire)
   local ok,p=pcall(jsonDecode,wire)
   if ok and type(p)=='table' then historyCache=p;guihooks.trigger('RacePrepBJRHistory',p) end
  end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepBJRHostStatus',function() hostSeen=clock end,'raceprepBJR')
  -- BJR's menu rail shows the Motorsport page (BJR plugin API): its buttons
  -- open this window on a section; the floating launch button is then hidden
  require('ge/extensions/raceprep/net').on('RacePrepRail',function() M.railPage=true end,'raceprepBJR')
  require('ge/extensions/raceprep/net').on('RacePrepOpen',function(section)
   if type(section)~='string' or not section:match('^%a+$') then return end
   -- 'full': BJR's full window opened our tab, so open full screen on the current tab
   M.openFull=section=='full'
   if not M.openFull then M.tab=section:sub(1,30) end
   M.visible=true;M.openRequest=(M.openRequest or 0)+1;nextPush=0;H.send('RacePrepGetChallenges',{});H.send('RacePrepGetPresets',{});H.send('RacePrepGetProgress',{})
  end,'raceprepBJR')
  if require('ge/extensions/raceprep/frontend').isCareer() or TriggerServerEvent then pcall(require('ge/extensions/raceprep/net').send,'RacePrepRailAsk','') end
  handlerRegistered=true
  H.send('RacePrepGetChallenges',{});H.send('RacePrepGetPresets',{});H.send('RacePrepGetProgress',{})
 end
 hookReady()
 local nowMs=GetCurrentTimeMillis and GetCurrentTimeMillis() or clock*1000
 if not careerMode() then autoWorker.update(dt or 0) end
 RivalsSession.update(nowMs)
 RivalsSession.draw(nowMs)
 fuelTick()
 refreshSelector()
 if uiReady and not careerMode() and clock>=nextDriving then
  local ok,packet=pcall(require('ge/extensions/raceprep/bjr/driving').packet,GetCurrentTimeMillis and GetCurrentTimeMillis() or clock*1000,clock)
  if ok then
   -- race timing itself is BJR's (BJRaceHud, read by the HUD in the UI)
   local activeOverlay=(packet.rivals and packet.rivals.active) or (packet.race~=nil) or (packet.practice~=nil) or (packet.announcement~=nil) or (next(packet.signals or {})~=nil)
   nextDriving=clock+(activeOverlay and .05 or .25)
   if activeOverlay or drivingIdleSent~=packet.active then
    drivingIdleSent=not activeOverlay and packet.active or nil
    guihooks.trigger('RacePrepBJRDriving',packet)
   end
   local r=packet.race or {}
   local status=tostring(r.state or 'no race')..(packet.active and '' or ' (BJR not ready)')
   if status~=lastTimingStatus then lastTimingStatus=status;if log then log('I','raceprepBJR','race state: '..status) end end
  else nextDriving=clock+.25;log('E','raceprepBJR','Driving HUD: '..tostring(packet)) end
 end
 if clock>=nextKTS then
  nextKTS=clock+1
  if radarEnabled and not ui_vehicleRadarApp and extensions and extensions.load then extensions.load('ui_vehicleRadarApp') end
  local d,v=data();lastVehicle=v or lastVehicle;local rt=runtime()
  for _,name in ipairs({'roadTemperature','luukstyrethermalsandwear','createbrakeductsliders'}) do
   if not rawget(_G,name) then
    if extChecked[name]==nil then extChecked[name]=FS and FS.fileExists and FS:fileExists('/lua/ge/extensions/'..name..'.lua')==true or false end
    if extChecked[name] and extensions and extensions.load then extensions.load(name) end
   end
  end
  local road=roadTemperature and roadTemperature.get and roadTemperature.get()
  if v then
   local id=v:getID()
   local temp=road and (road.track or road.roadC or road.roadTemp or road.trackTemp or road.temperature)
   v:queueLuaCommand('extensions.load("raceprepKTS") raceprepKTS.setRoadTemperature('..(tonumber(temp) and tostring(temp) or 'nil')..') obj:queueGameEngineLua("if raceprepBJR then raceprepBJR.onKTSStatus("..obj:getID()..","..serialize(raceprepKTS.status)..") end")')
   if rt and (not rt.diffReports[id] or diffVdata[id]~=(d and d.vdata)) then
    diffVdata[id]=d and d.vdata
    rt.requestDiffReport(id)
   end
  end
 end
 if uiReady and clock>=nextPush then
  nextPush=clock+.5
  local ok,state=pcall(M.snapshot)
  if ok then guihooks.trigger('RacePrepBJRState',state) else log('E','raceprepBJR',tostring(state)) end
 end
end
M.onKTSStatus=function(id,status)
 local v=own();if v and v:getID()==id and type(status)=="table" then M.kts=status end
end
M.onResults=function(wire)
 local ok,res=pcall(jsonDecode,wire);if ok and type(res)=="table" and type(res.rows)=="table" then
  local key=res.runID or res.key
  if not M.results or (M.results.runID or M.results.key)~=key then resultNotice=resultNotice+1;M.visible=true;M.tab="results" end
  M.results=res;nextPush=0
  historyAsked=-1e9;historyCache=nil;actions.history()
 end
end
M.onExtensionLoaded=function()
 Sidebar.start()
 if not raceprepRatings then extensions.load('raceprepRatings') end
end
M.onServerLeave=function()
 RivalsSession.stop();Strategy.reset();sharedTunesView={items={}}
 historyAsked=-1e9
 historyCache=nil
 guihooks.trigger('RacePrepBJRRivalNotice',{kind='clear'});guihooks.trigger('RacePrepBJRReward',{clear=true});autoWorker.disconnect();M.autoRatings=nil;guihooks.trigger('RacePrepBJRAutoRatings',{});M.challenges=nil;guihooks.trigger('RacePrepBJRChallenges',{});M.preparedRules=nil;M.preparedPreset=nil;M.presetLibrary=nil;local rt=runtime();if rt then rt.presetSessions=nil end;guihooks.trigger('RacePrepBJRPresets',{});M.driverCard=nil;M.progress=nil;M.progressHistory=nil;guihooks.trigger('RacePrepBJRProgress',{});guihooks.trigger('RacePrepBJRLeague',{});guihooks.trigger('RacePrepBJRHistory',{items={},records={}})
 Sidebar.reset()
 Selector.restore(selectorBinding);selectorBinding=nil;selectorStamp=nil
 require('ge/extensions/raceprep/bjr/driving').reset()
 guihooks.trigger('RacePrepBJRDriving',{active=false,signals={}})
 pending={tune=false,diff=false,upgrades=false};fuelOp=nil;fuelRestore=nil;fuelRows={};fuelTargets={};fuelRequest=nil;fuelOwner=nil
 drivingIdleSent=nil;diffVdata={}
 restoreReady();hostSeen=-1e9;M.results=nil;lastError=nil;M.kts=nil
 local rt=runtime();if rt then rt.rules=nil;rt.skills=nil;rt.motorsport=nil;rt.rolling={phase=nil} end
 local director=require('ge/extensions/raceprep/director');director.data=nil;director.lights=nil;director.hazards={};director.falseStart=nil
 local practice=require('ge/extensions/raceprep/session');practice.data=nil;practice.laps={};practice.lastLap=nil
 require('ge/extensions/raceprep/rubberLine').restore()
 require('ge/extensions/raceprep/rubberLine').clear()
 require('ge/extensions/raceprep/raceEnvironment').restore()
 require('ge/extensions/raceprep/weather').restore()
 local v=own() or lastVehicle
 if v then pcall(function() v:queueLuaCommand('if raceprepKTS then extensions.unload("raceprepKTS") end if raceprepLimits then raceprepLimits.disable() end') end) end
 lastVehicle=nil
 guihooks.trigger('RacePrepBJRState',{ready=false,visible=false})
 M.visible=false
end
M.onExtensionUnloaded=function()
 RivalsSession.stop()
 Sidebar.stop()
 Selector.restore(selectorBinding);selectorBinding=nil
 if guihooks then guihooks.trigger('RacePrepBJRDriving',{active=false,signals={}}) end
 local driving=package.loaded['ge/extensions/raceprep/bjr/driving'];if driving then driving.reset() end
 restoreReady()
 local v=own();if v then v:queueLuaCommand('if raceprepKTS then extensions.unload("raceprepKTS") end') end
end
-- frame-spike report: time this extension's per-frame update (raceprep/prof)
do local Prof=require('ge/extensions/raceprep/prof');Prof.hook();if M.onUpdate then M.onUpdate=Prof.wrap('raceprepBJR',M.onUpdate) end end
return M
