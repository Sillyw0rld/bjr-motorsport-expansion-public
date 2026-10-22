-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- Shared PI ratings, spawn collection, and reversible selector metadata badges.
-- AGPL-3.0-or-later (see LICENSE). Local physics remain client-enforced, like other Race Prep rules.
local rating=require("ge/extensions/raceprep/rating")
local identity=require("ge/extensions/raceprep/ratingIdentity")
local upgradeCatalog=require("ge/extensions/raceprep/upgrades").catalog
local M={vehicles={},statuses={},remoteVehicles={},carStatics={}}
local seed=jsonReadFile('/lua/ge/extensions/raceprep/ratings-seed.json') or {entries={}}
local entries,constants=deepcopy(seed.entries or {}),seed.constants
local candidates={}
-- Ratings of setups the player saved (Save setup): "model/config" -> entry.
-- Shown on the saved setup's selector tile before it is ever spawned.
local SAVED_FILE='/settings/raceprep/saved-setups.json'
local savedRatings=(jsonReadFile and jsonReadFile(SAVED_FILE)) or {}
-- model/config -> rating key of the factory .pc's parts (false: none); a
-- factory config does not change during a session
local partsKeyCache,resolveQueue,resolveQueued={},{},{}
local labelsFound=false
--- one queued config per call (from onUpdate): compile its .pc parts once
function M.resolveNext()
    local job=table.remove(resolveQueue,1)
    if not job then return false end
    resolveQueued[job.key]=nil
    local pk=false
    local pc=jsonReadFile and jsonReadFile('/vehicles/'..job.model..'/'..job.config..'.pc')
    if pc then
        local ok,res=pcall(require('jbeam/loader').loadJbeamOnlyConfig,{'/vehicles/'..job.model..'/','/vehicles/common/'},pc)
        if ok and res then pk=identity.key(job.model,job.config,identity.flatten(res.partsTree)) end
    end
    partsKeyCache[job.key]=pk
    return true,pk
end
M.resolvePending=function() return #resolveQueue end
local function indexEntries()
    candidates={}
    for _,e in pairs(entries) do if e.model and e.config then candidates[e.model..'/'..e.config]=true end end
end
indexEntries()
local clock,pending,requests=0,{},{}
local serverReady=false
local handlers=false
local nextRequest=0
local decorated={}
local decoratedModels={}
local decoratedBJI={}
local originalGetModel
local originalDisplayOptions
local originalSortFunction
local grouping
local originalClassGrouping
local selectorDirty=true
local nonce=0
local liveRequests,liveSnapshots,liveAsked={},{},{}
local identities={}
local beamJoyInstance
local modelNames={}
local lastPublish={} -- server vehicle id -> {sig, at}: rating re-send limit
-- ratings as the server sent them (key -> entry): a car whose rating is the
-- server's own copy is reported by key, without its parts list
local serverCopy,sendFull={},{}
local function rawOf(e,field)
    local r=type(e)=='table' and type(e.raw)=='table' and tonumber(e.raw[field])
    return r or (type(e)=='table' and tonumber(e[field])) or nil
end
local function withPotential(entry,model,vd)
    if not entry then return nil end
    local policy=require('ge/extensions/raceprep/tuningPolicy')
    local rpi=rawOf(entry,'pi')
    local bonus,share
    if vd then
        local ignored
        bonus,ignored,share=policy.bonus(vd,rpi)
    else
        local info=require('common/raceprep/engineSelection').catalog().models[model]
        bonus,share=policy.catalogBonus(entry.parts,info and info.raceParts,rpi)
    end
    -- Race weight reduction earns a Forza-style extra share (raceprep/weight)
    local weightShare=require('ge/extensions/raceprep/weight').bonusShare(entry.parts)
    -- Other clients use the exact bonus metadata reported by this car's owner,
    -- rather than inferring a different bonus from incomplete part catalogues.
    if not vd and type(entry.presentation)=='table' then
        share=entry.presentation.tuningShare or 0
        weightShare=entry.presentation.weightShare or 0
        bonus=math.floor((rpi or 0)*share+.5)
    end
    if bonus==0 and weightShare==0 then
        if type(entry.raw)=='table' or not (constants and constants.curve) then return entry end
        local out={}
        for key,value in pairs(entry) do out[key]=value end
        out.raw={pi=rawOf(entry,'pi'),pi_speed=rawOf(entry,'pi_speed'),pi_technical=rawOf(entry,'pi_technical')}
        for _,field in ipairs({'pi','pi_speed','pi_technical'}) do
            if out.raw[field] then out[field]=rating.curve(out.raw[field],constants or false) end
        end
        out.class=rating.classOf(out.pi)
        return out
    end
    local out={}
    for key,value in pairs(entry) do out[key]=value end
    local basePI=rpi and rating.curve(rpi,constants or false) or entry.pi
    out.performancePI=basePI
    local tunPI=rpi and (rating.curve(rpi*(1+share),constants or false)-basePI) or bonus
    local wgtPI=rpi and (rating.curve(rpi*(1+weightShare),constants or false)-basePI) or 0
    if tunPI>0 then out.tuningPotentialPI=tunPI end
    if wgtPI>0 then out.weightBonusPI=wgtPI end
    local raw={}
    for _,field in ipairs({'pi','pi_speed','pi_technical'}) do
        local rf=rawOf(entry,field)
        if rf then
            raw[field]=math.max(100,math.floor(rf*(1+share+weightShare)+.5))
            out[field]=rating.curve(rf*(1+share+weightShare),constants or false)
        end
    end
    if next(raw) then out.raw=raw end
    out.class=rating.classOf(out.pi)
    return out
end

local function vehicle(id)
    return getObjectByID and getObjectByID(id) or be:getObjectByID(id)
end
local function mpVehicle(id)
    return MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(id)
end
local function isLocal(id)
    local v=mpVehicle(id)
    return not v or v.isLocal==true
end
local function configKey(d)
    local fn=d.config and d.config.partConfigFilename
    if type(fn)=="string" then return fn:match('([^/\\]+)%.pc$') or 'default' end
    return 'default'
end
local function currentIdentity(id)
    local d=core_vehicle_manager.getVehicleData(id)
    if not d or not d.vdata then return end
    local cached=identities[id]
    if cached and cached.bundle==d and cached.vdata==d.vdata then return cached end
    local model=d.vdata.model or (vehicle(id) and vehicle(id).JBeam)
    if not model then return end
    local parts=d.vdata.activeParts or identity.flatten(d.config.partsTree)
    local out={model=model,config=configKey(d),parts=parts,
        key=identity.key(model,configKey(d),parts),bundle=d,vdata=d.vdata}
    identities[id]=out
    return out
end
M.identity=currentIdentity
local function badge(e) return e and string.format("%s %d",e.class,e.pi) or "Rating pending" end
M.badge=badge
function M.getConfig(model,config)
    local key=seed.baselines and seed.baselines[model..'/'..config]
    if key and entries[key] then return withPotential(entries[key],model) end
    local c=core_vehicles and core_vehicles.getConfig(model,config)
    return c and c.RacePrepRating
end
function M.onLiveSnapshot(id,token,data)
    if liveRequests[id]~=token then return end
    liveRequests[id]=nil
    if not data.error then
        local d=core_vehicle_manager and core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(id)
        data.vdata=d and d.vdata or nil
        liveSnapshots[id]=data
    end
end
function M.getLiveCarData(id)
    local d=core_vehicle_manager and core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(id)
    local vd=d and d.vdata or nil
    local snap=liveSnapshots[id]
    if snap and snap.vdata~=vd then snap=nil;liveSnapshots[id]=nil end
    if liveRequests[id] and clock-(liveAsked[id] or clock)>10 then liveRequests[id]=nil end
    if not snap and not liveRequests[id] and clock-(liveAsked[id] or -10)>=5 then
        local veh=vehicle(id)
        if veh and isLocal(id) then
            nonce=nonce+1
            local token='live-'..nonce
            liveRequests[id],liveAsked[id]=token,clock
            veh:queueLuaCommand(string.format('extensions.load("raceprepRating") raceprepRating.snapshot(%q)',token))
        end
    end
    return snap
end
function M.getCarData(id)
    local d=core_vehicle_manager and core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(id)
    local rev=d and d.vdata and tostring(d.vdata)
    if M.carStatics[id] and rev and M.carStatics[id]._rev and M.carStatics[id]._rev~=rev then M.carStatics[id]=nil end
    if not M.carStatics[id] and not pending[id] and not requests[id] then M.getStats(id) end
    return M.carStatics[id]
end
function M.getVehicle(id)
    local i=currentIdentity(id)
    if not i then return nil,"Choose a car first" end
    return withPotential(entries[i.key],i.model,i.bundle.vdata),not entries[i.key] and (M.statuses[id] or "Waiting for car rating") or nil
end
--- rating of one car on the server, by BeamMP's "playerID-vid" id (BJR's
--- player list shows one row per car; its own label is per model)
function M.getServerVehicle(sid)
    sid=tostring(sid or '')
    local owner=sid:match('^(%d+)%-')
    local mine
    for _,v in pairs(MPVehicleGE and MPVehicleGE.getVehicles and MPVehicleGE.getVehicles() or {}) do
        if v.serverVehicleString==sid and v.gameVehicleID then mine=v end
    end
    if mine and isLocal(mine.gameVehicleID) then return (M.getVehicle(mine.gameVehicleID)) end
    local key=owner and (M.remoteVehicles[owner] or {})[sid]
    if key and entries[key] then return withPotential(entries[key],entries[key].model) end
    if mine then return (M.getVehicle(mine.gameVehicleID)) end
end
function M.getPlayer(playerID)
    local BJI_Context,BJI_Veh=Platform.get("BJI_Context"),Platform.get("BJI_Veh")
    local own=BJI_Context and BJI_Context.User and BJI_Context.User.playerID
    if own==playerID and BJI_Veh and BJI_Veh.getCurrentVehicleOwn then
        local v=BJI_Veh.getCurrentVehicleOwn()
        if v then return M.getVehicle(v:getID()) end
    end
    local group=M.remoteVehicles[tostring(playerID)] or {}
    local player=BJI_Context and BJI_Context.Players and BJI_Context.Players[playerID]
    local active=player and player.currentVehicle
    if MPVehicleGE and MPVehicleGE.getVehicles then
        for _,v in pairs(MPVehicleGE.getVehicles()) do
            if v.ownerID==playerID and v.isSpawned and not v.isDeleted and
                    (not active or v.remoteVehID==active or v.gameVehicleID==active) then
                local key=group[v.serverVehicleString]
                -- same PI as the owner sees: race-part tuning potential and the
                -- race body bonus included (they were missing for other drivers)
                if key and entries[key] then return withPotential(entries[key],entries[key].model) end
                local e=M.getVehicle(v.gameVehicleID);if e then return e end
            end
        end
    end
    -- Avoid choosing an arbitrary car from a multi-vehicle owner's roster.
    local sole,count=nil,0
    for _,key in pairs(group) do sole=key;count=count+1 end
    if count==1 and entries[sole] then return withPotential(entries[sole],entries[sole].model) end
end
-- Upgrades / other part combinations of a car with a measured or calibrated
-- stock rating are anchored to it: PI = stock PI + (formula now - formula of
-- the stock config). The formula's per-car bias (tyres, aero, how the export
-- was built) cancels; only the change from the parts is estimated. Stock
-- formula values ship in the seed ("formula").
local function anchorBase(model,config,parts)
    return require('ge/extensions/raceprep/anchorSelection').select(seed,model,config,parts)
end
M.anchorBase=anchorBase
local function anchor(e,model,config,parts)
    local base,key=anchorBase(model,config or e.config,parts or e.parts)
    if not base then
        if type(e.raw)~='table' then
            e.raw={pi=e.pi,pi_speed=e.pi_speed,pi_technical=e.pi_technical}
            for _,f in ipairs({'pi','pi_speed','pi_technical'}) do
                if e.raw[f] then e[f]=rating.curve(e.raw[f],constants or false) end
            end
            if e.pi then e.class=rating.classOf(e.pi) end
        end
        return e
    end
    local raw={}
    for _,f in ipairs({'pi','pi_speed','pi_technical'}) do
        local b,fb,ef=rawOf(base,f),tonumber(base.formula[f]),rawOf(e,f)
        if b and fb and ef then
            raw[f]=math.max(100,math.floor(b+(ef-fb)+0.5))
            e[f]=rating.curve(raw[f],constants or false)
        end
    end
    if next(raw) then e.raw=raw end
    e.class=rating.classOf(e.pi)
    e.anchored=true
    e.anchorKey=key
    e.method='anchored to the '..tostring(base.source)..' stock rating'
    return e
end
M.anchor=anchor
-- a blind computed entry that can now be anchored is recomputed
local function stale(e,model,config,parts)
    if not e or e.source~='computed' then return false end
    -- Legacy servers do not retain anchorKey. Keep their cache policy until
    -- a coordinated seed migration, rather than recollecting on every sync.
    return not e.anchored and anchorBase(model,config or e.config,parts or e.parts)~=nil
end
local function publish(id,i,e)
    if not serverReady or not TriggerServerEvent or not isLocal(id) then return end
    local v=mpVehicle(id)
    local sid=v and v.serverVehicleString
    if not sid and MPVehicleGE and MPVehicleGE.getServerVehicleID then sid=MPVehicleGE.getServerVehicleID(id) end
    if not sid then return end
    local owner=tostring(v and v.ownerID or sid:match('^(%d+)%-'))
    local _,_,share=require('ge/extensions/raceprep/tuningPolicy').bonus(i.bundle.vdata,e.pi)
    local weightShare=require('ge/extensions/raceprep/weight').bonusShare(i.parts)
    if not i.carName then
        if not modelNames[i.model] then
            local info=core_vehicles and core_vehicles.getModel and core_vehicles.getModel(i.model)
            modelNames[i.model]=tostring(info and info.model and info.model.Name or i.model:gsub('_',' ')):gsub('%s*%[[EDCBASRPX] %d+%]$',''):sub(1,120)
        end
        i.carName=modelNames[i.model]
    end
    -- shares rounded and compared with a tolerance: summed shares (.025+.015)
    -- do not survive the server's JSON round trip bit for bit, and an exact
    -- comparison re-sent the full parts list every 5 s (2026-10-18 zlib warnings)
    local function r4(x) return math.floor((tonumber(x) or 0)*10000+.5)/10000 end
    local function same(a,b) return math.abs((tonumber(a) or -1)-(tonumber(b) or -2))<1e-6 end
    share,weightShare=r4(share),r4(weightShare)
    local meta={tuningShare=share,weightShare=weightShare,carName=i.carName}
    local confirmed=M.remoteVehicles[owner];local got=e.presentation
    if confirmed and confirmed[sid]==i.key and got and same(got.tuningShare,share) and same(got.weightShare,weightShare) and got.carName==meta.carName then return end
    -- safety net: an identical report goes out at most once a minute, whatever
    -- keeps the server's copy from matching (the parts list is large)
    local sig=i.key..'|'..share..'|'..weightShare..'|'..tostring(e.pi)
    local last=lastPublish[sid]
    if last and last.sig==sig and clock-last.at<60 then return end
    lastPublish[sid]={sig=sig,at=clock}
    -- the full parts list compresses past BeamMP's 5:1 unpack buffer (a 30 MB
    -- retry on the server, "zlib uncompress() failed"): send it only for a
    -- rating the server does not hold yet, or when the server asks for it
    if serverCopy[i.key]==e and not sendFull[sid] then
        require('ge/extensions/raceprep/net').send('RacePrepComputedRating',jsonEncode({model=i.model,key=i.key,serverVehicleID=tostring(sid),presentation=meta}))
        return
    end
    sendFull[sid]=nil
    require('ge/extensions/raceprep/net').send('RacePrepComputedRating',jsonEncode({model=i.model,config=i.config,parts=i.parts,
        serverVehicleID=tostring(sid),pi=e.pi,pi_speed=e.pi_speed,pi_technical=e.pi_technical,raw=e.raw,anchored=e.anchored==true,presentation=meta}))
end
local function decorate(model)
    local single, count, default, factory, factoryCount
    count,factoryCount=0,0
    local defaultKey=model and model.model and model.model.default_pc
    for _,c in pairs(model and model.configs or {}) do
        count=count+1
        local key=(c.model_key or model.model.key)..'/'..c.key
        local baseline=seed.baselines and seed.baselines[key]
        local e=baseline and entries[baseline]
        if not e then e=savedRatings[key] end
        if not e and candidates[key] then
            -- An unknown configuration is advertised only for its actual .pc parts,
            -- never label a stock selector tile with an upgraded spawn's PI.
            -- Resolving them compiles the config's jbeam: cached per config and
            -- done in the background (M.resolveNext), never while the selector
            -- builds its tiles (that was the spike when opening Spawn vehicle).
            local pk=partsKeyCache[key]
            if pk then e=entries[pk]
            elseif pk==nil and not resolveQueued[key] then
                resolveQueued[key]=true;resolveQueue[#resolveQueue+1]={key=key,model=c.model_key,config=c.key}
            end
        end
        if e then
            single=e
            -- the model tile shows the default (stock) rating even when the
            -- player has saved setups of their own next to it
            if defaultKey and c.key==defaultKey then default=e end
            if baseline and entries[baseline] then factory=e;factoryCount=factoryCount+1 end
            if not decorated[c] then decorated[c]={Configuration=c.Configuration,Name=c.Name,performance=c['Performance Class'],PI=c.PI} end
            local original=decorated[c]
            c.Configuration=(original.Configuration or c.key)..'  ['..badge(e)..']'
            c.Name=(original.Name or original.Configuration or c.key)..'  ['..badge(e)..']'
            c['Performance Class'],c.PI=e.class,e.pi
            c.RacePrepRating=e
        end
    end
    local shown=default or (factoryCount==1 and factory) or (count==1 and single)
    if model and model.model and shown then
        local m=model.model
        if not decoratedModels[m] then decoratedModels[m]={Name=m.Name,performance=m['Performance Class']} end
        m.Name=(decoratedModels[m].Name or m.key)..'  ['..badge(shown)..']'
        m['Performance Class']=shown.class
    end
    return model
end
local function decorateBJI(catalogue)
    for _,model in pairs(catalogue or {}) do
        if type(model)=='table' and type(model.configs)=='table' then
            for _,config in pairs(model.configs) do
                local modelKey=config.model_key or model.key
                local e=modelKey and config.key and M.getConfig(modelKey,config.key)
                if e and config.label then
                    if not decoratedBJI[config] then decoratedBJI[config]=config.label end
                    local base=decoratedBJI[config]:gsub('%s*%[[EDCBASRPX] %d+%]$','')
                    config.label=base..'  ['..badge(e)..']'
                end
            end
        end
    end
end
local function restoreMetadata()
    for c,original in pairs(decorated) do
        c.Configuration,c.Name,c['Performance Class'],c.PI=original.Configuration,original.Name,original.performance,original.PI
        c.RacePrepRating=nil
    end
    for m,original in pairs(decoratedModels) do m.Name,m['Performance Class']=original.Name,original.performance end
    for c,original in pairs(decoratedBJI) do c.label=original end
end
function M.decorateSelector()
    local BJI_Veh=Platform.get("BJI_Veh")
    if not core_vehicles then return end
    restoreMetadata()
    if core_vehicles.getModel~=originalGetModel and not originalGetModel then
        originalGetModel=core_vehicles.getModel
        M.modelWrapper=function(...) return decorate(originalGetModel(...)) end
        core_vehicles.getModel=M.modelWrapper
    end
    local models={}
    for _,e in pairs(entries) do models[e.model]=true end
    -- only mounted cars: at join, Automation mods mount after the ratings arrive, and
    -- looking those up early logs "Vehicle not available" for every one of them
    local exists=FS and FS.directoryExists and function(m) return FS:directoryExists('/vehicles/'..m) end or function() return true end
    for model in pairs(models) do if exists(model) then core_vehicles.getModel(model) end end
    -- BeamJoy has its own copied labels, often populated before this add-on
    -- mounts. Refresh those too; changing native metadata alone is insufficient.
    if BJI_Veh then decorateBJI(BJI_Veh.allVehicleConfigs) end
    local chooser=rawget(_G,'BJI_Win_VehSelector')
    if chooser then
        for _,catalogue in pairs(chooser.models or {}) do decorateBJI(catalogue) end
        for _,catalogue in pairs(chooser.cache and chooser.cache.vehicles or {}) do decorateBJI(catalogue) end
    end
    if ui_vehicleSelector_general and ui_vehicleSelector_general.clearCache then
        ui_vehicleSelector_general.clearCache()
    end
    local general=ui_vehicleSelector_general
    if general and not originalDisplayOptions then
        originalDisplayOptions=general.getDisplayDataOptions
        M.optionsWrapper=function(...)
            local options=originalDisplayOptions(...)
            for _,option in ipairs(options) do
                local wanted=option.key=='groupMode' and 'Performance Class' or option.key=='sortMode' and 'PI'
                if wanted then
                    local found=false
                    for _,choice in ipairs(option.options or {}) do if choice.value==wanted then found=true end end
                    if not found then table.insert(option.options,{label=wanted,value=wanted,racePrep=true}) end
                end
            end
            return options
        end
        general.getDisplayDataOptions=M.optionsWrapper
        grouping=require('/lua/ge/extensions/ui/vehicleSelector/tileGrouping')
        originalClassGrouping=grouping.groupModeFunctions['Performance Class']
        grouping.groupModeFunctions['Performance Class']=function(c)
            for i,class in ipairs(rating.classes) do if c==class then return 'Class '..class,i end end
            return c or 'Unrated',99
        end
        local sorting=require('/lua/ge/extensions/ui/vehicleSelector/tileSorting')
        originalSortFunction=sorting.getSortFunction
        M.sortWrapper=function(mode)
            if mode~='PI' then return originalSortFunction(mode) end
            return function(a,b)
                local ea=a.model_key and a.config_key and M.getConfig(a.model_key,a.config_key)
                local eb=b.model_key and b.config_key and M.getConfig(b.model_key,b.config_key)
                local pa=(ea and ea.pi) or tonumber((a.name or ''):match('%[[A-Z] (%d+)%]')) or 1000
                local pb=(eb and eb.pi) or tonumber((b.name or ''):match('%[[A-Z] (%d+)%]')) or 1000
                if pa==pb then return (a.name or '')<(b.name or '') end
                return pa<pb
            end
        end
        sorting.getSortFunction=M.sortWrapper
    end
    selectorDirty=false
end
-- the server lacks the rating a short report named: send the full report next pass
function M.onRatingMissing(sid)
    if type(sid)=='string' and sid~='' then sendFull[sid]=true;lastPublish[sid]=nil end
end
function M.onRatings(payload)
    local ok,d=pcall(jsonDecode,payload)
    if not ok or type(d)~='table' or type(d.entries)~='table' then return end
    -- seed entries arrive without their parts lists: restore from the local seed
    local function restore(k,v)
        if type(v)=='table' and v.parts==nil and seed.entries and seed.entries[k] then v.parts=seed.entries[k].parts end
        return v
    end
    if d.delta then
        -- one change (new rating, car mapping, removed car or player)
        for k,v in pairs(d.entries) do entries[k]=restore(k,v);serverCopy[k]=entries[k] end
        for pid,map in pairs(type(d.vehicles)=='table' and d.vehicles or {}) do
            if map==false then M.remoteVehicles[pid]=nil
            elseif type(map)=='table' then
                M.remoteVehicles[pid]=M.remoteVehicles[pid] or {}
                for sid,key in pairs(map) do M.remoteVehicles[pid][sid]=key or nil end
            end
        end
        if not serverReady then return end -- a delta before the full store: wait for it
    else
        entries=d.entries;serverCopy={}
        for k,v in pairs(entries) do serverCopy[k]=restore(k,v) end
        if d.constants then constants=d.constants end
        M.remoteVehicles=type(d.vehicles)=='table' and d.vehicles or {}
    end
    indexEntries()
    serverReady=true
    -- only entries change the car list (a mapping-only delta must not make
    -- the vehicle selector rebuild)
    if not d.delta or next(d.entries) then
        M.catalogRevision=(M.catalogRevision or 0)+1
        selectorDirty=true
    end
    for id in pairs(M.vehicles) do
        local i=currentIdentity(id)
        if i then
            M.vehicles[id]=i.key
            if entries[i.key] and not stale(entries[i.key],i.model,i.config,i.parts) then publish(id,i,entries[i.key]) else pending[id]=clock+0.5 end
        end
    end
end
-- performance figures (declared before onStatic, which routes their replies)
local onStats -- defined with the performance figures below
local stats,statsRequests={},{}
--- remember the car's current rating for a setup just saved under `name`
function M.rememberSavedSetup(id,name)
    local i=currentIdentity(id)
    if not i or type(name)~='string' or name=='' then return false end
    local e=withPotential(entries[i.key],i.model,i.bundle.vdata)
    if not e then return false,'rating pending' end
    local copy={};for k,v in pairs(e) do copy[k]=v end
    copy.config,copy.savedSetup,copy.savedFrom=name,true,i.config
    savedRatings[i.model..'/'..name]=copy
    if jsonWriteFile then jsonWriteFile(SAVED_FILE,savedRatings,true) end
    selectorDirty=true
    return true,copy
end
function M.onStatic(id,requestID,st)
    local sr=statsRequests[id]
    if sr and sr.token==requestID then return onStats(id,sr,st) end
    local request=requests[id]
    if not request or request.token~=requestID then return end
    requests[id]=nil
    local i=currentIdentity(id)
    if not i or i.key~=request.identity.key then pending[id]=clock+0.5;return end
    if st.error then M.statuses[id]='Car rating unavailable';log('W','raceprepRatings',st.error);return end
    -- formula v7: native cars' probed aero (only with the v7 constants, whose
    -- native factors were fitted together with it)
    if constants and constants.v7 and not st.nativeAero then
        st.nativeAero=require('ge/extensions/raceprep/nativeAero').lookup(i.model,i.config,i.parts)
    end
    local e,err=rating.compute(st,constants,st.drive or request.drive)
    if not e then M.statuses[id]='Car rating unavailable';log('W','raceprepRatings',tostring(err));return end
    st._rev=tostring(i.vdata)
    M.carStatics[id]=st
    -- st was collected at the rated point (default vars, max-rated parts):
    -- it must not seed stats[], the tuning-aware performance cache. getStats
    -- issues its own collection for the car's current settings.
    e.model,e.config,e.parts,e.partsHash=i.model,i.config,i.parts,identity.hash(i.parts)
    if i.model=='firestarter_clone_kalalalac' then e.flag='Suspected gearbox fault: hunts / 134 km/h' end
    -- seed notes for configs rated by the formula on purpose (e.g. spun in the rig test)
    e.flag=e.flag or (seed.flags and seed.flags[i.model..'/'..tostring(i.config)])
    e=anchor(e,i.model)
    -- Seed/server entries (especially measured/sibling values) take precedence.
    if not entries[i.key] or stale(entries[i.key],i.model) then
        entries[i.key]=e;indexEntries();selectorDirty=true
        M.catalogRevision=(M.catalogRevision or 0)+1
    end
    M.vehicles[id],M.statuses[id]=i.key,nil
    publish(id,i,entries[i.key])
end
-- The compact car table the vehicle-side collector reads. Rating: vd is the
-- car compiled with no tuning vars (tuning never changes PI). Stats (live):
-- vd is the car as loaded, tuning included; race brakes at their actual Brake
-- Power and aero kits at their slider settings instead of rated maximum.
local function shadowData(i,vd,live,vars)
    return require('ge/extensions/raceprep/ratingShadow').build(i,vd,live,vars,upgradeCatalog)
end

---------------------------------------------------------------- performance
-- Setup panel figures (acceleration, braking, lateral g, top speed) for the car as
-- loaded, tuning included. Separate from the rating: PI never sees tuning.
-- Measured cars: rig figure x (model now / model of the stock car).
local perfSeed=(jsonReadFile and jsonReadFile('/lua/ge/extensions/raceprep/performance-seed.json') or {}).cars or {}
local PERF_KEYS={'zeroTo60','sixtyTo100','brake60','brake120','lat60','lat120','topSpeed'}
function M.anchorPerformance(model,live,config,native,parts)
    local seed=perfSeed[model]
    if native then seed=require('ge/extensions/raceprep/nativePerformance').select(perfSeed,model,config,parts) end
    local out={}
    for _,k in ipairs(PERF_KEYS) do
        local v=live[k];local m=seed and seed.model or {};local r=seed and seed.measured or {}
        if v and r[k] and m[k] and m[k]>0 then out[k]=r[k]*v/m[k]
        elseif v and k=='lat120' and r.lat60 and m.lat60 and m.lat60>0 then out[k]=r.lat60*v/m.lat60
        elseif v then out[k]=v;out.estimated=out.estimated or {};out.estimated[k]=true end
    end
    out.measured=seed~=nil
    return out
end
function M.getStats(id)
    local d=core_vehicle_manager.getVehicleData(id)
    if not d or not d.vdata or not constants or not isLocal(id) then return nil end
    local rev=tostring(d.vdata);local s=stats[id]
    if s and s.rev==rev then return s.values,s.prev end
    local r=statsRequests[id]
    if not r or r.rev~=rev or clock-r.at>5 then
        local i=currentIdentity(id);if not i then return s and s.values,s and s.prev end
        local ok,data=pcall(shadowData,i,d.vdata,true,d.config.vars or {})
        if not ok then return s and s.values,s and s.prev end
        local info=core_vehicles.getConfig(i.model,i.config)
        nonce=nonce+1
        statsRequests[id]={token='stats-'..nonce,rev=rev,model=i.model,drive=info and info.Drivetrain,at=clock,
            identity={config=i.config,parts=deepcopy(i.parts)}}
        vehicle(id):queueLuaCommand(string.format('extensions.load("raceprepRating") raceprepRating.collect(%s,%q)',serialize(data),statsRequests[id].token))
    end
    return s and s.values,s and s.prev
end
onStats=function(id,r,st)
    statsRequests[id]=nil
    -- the car changed (parts, tuning, respawn) while this collection ran:
    -- reject the reply instead of caching stale figures
    local d=core_vehicle_manager and core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(id)
    if not d or not d.vdata or tostring(d.vdata)~=r.rev then return end
    if st.error then return end
    if constants and constants.v7 and not st.nativeAero then
        local i=currentIdentity(id)
        if i then st.nativeAero=require('ge/extensions/raceprep/nativeAero').lookup(i.model,i.config,i.parts) end
    end
    st._rev=r.rev
    M.carStatics[id]=st
    local live=rating.performance(st,constants,st.drive or r.drive)
    if not live then return end
    local old=stats[id]
    stats[id]={rev=r.rev,model=r.model,values=(st.engineKind and st.engineKind.supported and st.engineKind.kind~='automation')
        and M.anchorPerformance(r.model,live,r.identity and r.identity.config,true,r.identity and r.identity.parts)
        or M.anchorPerformance(r.model,live),prev=old and old.model==r.model and old.values or nil}
end
local function collect(id)
    local i=currentIdentity(id)
    if not i or not isLocal(id) then return end
    M.vehicles[id]=i.key
    local veh=vehicle(id)
    if entries[i.key] and not stale(entries[i.key],i.model,i.config,i.parts) then
        M.statuses[id]=nil
        if veh then veh:queueLuaCommand('extensions.load("raceprepPower") raceprepPower.apply()') end
        publish(id,i,entries[i.key])
        return
    end
    if not constants then M.statuses[id]='Waiting for rating model';pending[id]=clock+2;return end
    M.statuses[id]='Calculating car rating'
    local d=i.bundle
    -- no tuning vars (tuning never changes PI), except the factory config's
    -- own boost and rev limit (raceprep/factoryEngine)
    local saved=savedRatings[i.model..'/'..tostring(i.config)]
    local cfg=deepcopy(d.config);cfg.vars=require('ge/extensions/raceprep/factoryEngine').vars(i.model,i.config,saved and saved.savedFrom)
    local ok,bundle=pcall(require('jbeam/loader').loadJbeam,id,nil,d.vdata.directoriesLoaded,cfg)
    if not ok or not bundle then M.statuses[id]='Rating unavailable: default-parts compilation failed';return end
    local vd=bundle.vdata
    local data=shadowData(i,vd,false,{})
    -- Native export upgrades have no Race Prep controller of their own.
    -- Load the bridge after powertrain initialization for those parts too.
    veh:queueLuaCommand('extensions.load("raceprepPower") raceprepPower.apply()')
    local info=core_vehicles.getConfig(i.model,i.config)
    nonce=nonce+1
    local token=tostring(nonce)
    requests[id]={token=token,identity=i,drive=info and info.Drivetrain,at=clock}
    veh:queueLuaCommand(string.format('extensions.load("raceprepRating") raceprepRating.collect(%s,%q)',serialize(data),token))
end
function M.onVehicleSpawned(id) liveRequests[id],liveSnapshots[id],liveAsked[id]=nil,nil,nil;M.carStatics[id]=nil;pending[id]=clock+1;requests[id]=nil;M.vehicles[id]=nil;identities[id]=nil end
function M.onVehicleDestroyed(id) liveRequests[id],liveSnapshots[id],liveAsked[id]=nil,nil,nil;M.carStatics[id]=nil;pending[id]=nil;requests[id]=nil;M.vehicles[id]=nil;M.statuses[id]=nil;identities[id]=nil end
function M.onVehicleSelectorOpen() selectorDirty=true end
function M.onExtensionLoaded()
    for _,v in pairs(getAllVehicles() or {}) do pending[v:getID()]=clock+1 end
end
function M.onUpdate(dt)
    local BJI,BJI_Windows=Platform.get("BJI"),Platform.get("BJI_Windows")
    clock=clock+(dt or 0)
    local instance=Platform.isBJR() and rawget(_G,"beamjoy_cache") or BJI_Windows and BJI_Windows.windows
    if instance and instance~=beamJoyInstance then
        beamJoyInstance=instance;serverReady=false;nextRequest=0;handlers=false
        M.remoteVehicles={};serverCopy={};sendFull={}
        entries=deepcopy(seed.entries or {});indexEntries();selectorDirty=true
        for id in pairs(M.vehicles) do if isLocal(id) then pending[id]=clock+0.5 end end
    end
    if not handlers and AddEventHandler then
        AddEventHandler('RacePrepRatings',M.onRatings,'raceprepRatings')
        AddEventHandler('RacePrepRatingMissing',M.onRatingMissing,'raceprepRatings')
        handlers=true
    end
    if handlers and clock>=nextRequest and BJI and BJI.CLIENT_READY then
        nextRequest=clock+5
        if not serverReady then TriggerServerEvent('RacePrepGetRatings','')
        else
            for id in pairs(M.vehicles) do
                if isLocal(id) then
                    local i=currentIdentity(id)
                    if i and entries[i.key] then publish(id,i,entries[i.key]) end
                end
            end
        end
    end
    for id,at in pairs(pending) do
        if clock>=at then
            pending[id]=nil
            local ok,err=pcall(collect,id)
            if not ok then M.statuses[id]='Car rating unavailable';log('W','raceprepRatings',tostring(err)) end
        end
    end
    for id,r in pairs(requests) do
        if clock-r.at>10 then requests[id]=nil;M.statuses[id]='Rating unavailable: collection timed out' end
    end
    -- background: one queued selector config per frame; labels refresh once
    -- when the queue is done and something new was found
    if #resolveQueue>0 then
        local _,pk=M.resolveNext()
        if pk and entries[pk] then labelsFound=true end
        if #resolveQueue==0 and labelsFound then labelsFound=false;selectorDirty=true end
    end
    if selectorDirty and clock>=1 then
        local ok,err=pcall(M.decorateSelector)
        if not ok then selectorDirty=false;log('W','raceprepRatings','Selector decoration: '..tostring(err)) end
    end
end
function M.onClientEndMission()
    serverReady=false;nextRequest=0;beamJoyInstance=nil;M.remoteVehicles={}
    entries=deepcopy(seed.entries or {})
    indexEntries()
    pending,requests={},{};identities={};M.vehicles={};M.statuses={};selectorDirty=true
end
function M.onExtensionUnloaded()
    if core_vehicles and core_vehicles.getModel==M.modelWrapper then core_vehicles.getModel=originalGetModel end
    restoreMetadata()
    if ui_vehicleSelector_general then
        if ui_vehicleSelector_general.getDisplayDataOptions==M.optionsWrapper then
            for _,option in ipairs(originalDisplayOptions()) do
                for i=#(option.options or {}),1,-1 do if option.options[i].racePrep then table.remove(option.options,i) end end
            end
            ui_vehicleSelector_general.getDisplayDataOptions=originalDisplayOptions
        end
        ui_vehicleSelector_general.clearCache()
    end
    if grouping then grouping.groupModeFunctions['Performance Class']=originalClassGrouping end
    if originalSortFunction then
        local sorting=require('/lua/ge/extensions/ui/vehicleSelector/tileSorting')
        if sorting.getSortFunction==M.sortWrapper then sorting.getSortFunction=originalSortFunction end
    end
end
-- frame-spike report: time this extension's per-frame update (raceprep/prof)
do local Prof=require('ge/extensions/raceprep/prof');Prof.hook();if M.onUpdate then M.onUpdate=Prof.wrap('raceprepRatings',M.onUpdate) end end
return M
