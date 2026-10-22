-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Car upgrades, Forza style (GE side, RacePrep add-on): the parts each slot
-- of the driver's car can take, grouped Engine / Drivetrain / Suspension and
-- brakes / Wheels and tyres / Nitrous, from BeamNG's own part database (the
-- same list as the vehicle config menu). Applying a part rebuilds the car
-- (core_vehicle_partmgmt.setPartsTreeConfig, synced by BeamMP like any config
-- change); the car rating is recomputed for the new parts automatically
-- (raceprepRatings), and the window shows old -> new PI with an Undo.
--
-- Where: free roam, and a BeamJoy race grid when the race rules allow parts
-- changes for that group (rules.parts[group] ~= "stock", nitrous allowed).
-- Class / PI limits are enforced at Ready like any car.

local U = {}
local Effects=require("ge/extensions/raceprep/upgradeEffects")
local EngineEffects=require('common/raceprep/engineEffects')
local EngineSelection=require('common/raceprep/engineSelection')
local Conversions=require('ge/extensions/raceprep/engineConversions')
local DrivetrainConversions=require('ge/extensions/raceprep/drivetrainConversions')
local function indexCatalog(c)
    c=c or {parts={},stocks={}}
    c.parts=c.parts or {}
    c.stocks=c.stocks or {}
    local byModel={}
    for name,p in pairs(c.parts) do
        if type(p)=='table' and p.model then
            local m=byModel[p.model]
            if not m then m={};byModel[p.model]=m end
            m[name]=p
        end
    end
    c.byModel,c._indexedParts=byModel,c.parts
    return c
end
local catalog=indexCatalog(jsonReadFile and jsonReadFile('/lua/ge/extensions/raceprep/upgrade-parts.json'))
U.catalog=catalog
U.indexCatalog=indexCatalog
function U.modelParts(c,model)
    if not c or not model then return {} end
    if c._indexedParts~=c.parts or not c.byModel then indexCatalog(c) end
    return c.byModel[model] or {}
end
U.engineInfo=function(model,parts)
    return EngineSelection.info(model,parts)
end
local function copySpec(spec)
    local out={}
    for key,value in pairs(spec or {}) do out[key]=value end
    return out
end
U.engineCurves=function(vehID)
    local r=rawget(_G,'raceprepRatings')
    local live=r and r.getLiveCarData and r.getLiveCarData(vehID)
    local canonical=r and r.getCarData and r.getCarData(vehID)
    if not live or not canonical then return nil end
    local d=core_vehicle_manager.getVehicleData(vehID)
    local model=d.vdata.model or d.config.model
    local info=U.engineInfo(model,d.vdata.activeParts)
    local spec=EngineSelection.spec(model,d.vdata.activeParts,d.config.vars,d.vdata)
    if not info or not spec then
        local engine=live.engines and live.engines[1]
        if not engine then return nil end
        return {current=engine.torque,limit=engine.maxRPM}
    end
    local base=live.stageBaseEngines and live.stageBaseEngines[1] and live.stageBaseEngines[1].torque
    if not base then
        for _,key in ipairs({'intake','exhaust','ecu','cam','forged','displacement','flywheel','induction','intercooler','oilcooler'}) do if spec[key] then return nil end end
        base=canonical.engines and canonical.engines[1] and canonical.engines[1].torque
    end
    if not base then return nil end
    return {stock=base,current=live.engines[1].torque,spec=spec,limit=info.stockRevLimit,info=info}
end
U.partEffect=function(vehID,name)
    local d=core_vehicle_manager and core_vehicle_manager.getVehicleData(vehID)
    local model=d and (d.vdata.model or d.config.model)
    local engine=model and U.engineInfo(model,d.vdata.activeParts)
    local conversion=model and Conversions.option(model,name)
    if conversion and not conversion.stock then
        return conversion.title,string.format('%s donor engine. Engine block %.1f kg (%+.1f kg). Export power; dyno updates after Apply. Original engine visuals and audio retained.%s',conversion.model,conversion.engineKG,conversion.massDeltaKG,conversion.fuelTank and (' Matching '..conversion.fuelTank.fuel..' tank fitted automatically; original capacity retained.') or '')
    end
    local dtConversion=model and DrivetrainConversions.option(model,name)
    if dtConversion and not dtConversion.stock then
        return dtConversion.title,string.format('%s donor architecture (%s, %+.1f kg). Preserves the fitted engine, gearbox and %.2f:1 final drive; updates driven axles and differentials.',dtConversion.donor,dtConversion.layout,tonumber(dtConversion.massDeltaKG) or 0,tonumber(dtConversion.finalDriveRatio) or 0)
    end
    local option=engine and engine.parts[name]
    if option then
        local curves=U.engineCurves(vehID)
        if not curves then return option.title..': reading dyno...', 'Reading the loaded engine curve.' end
        local before=copySpec(curves.spec)
        for kind,slot in pairs(engine.slots) do
            if slot==option.slot then
                before[kind]=nil
                if kind=='induction' then before.turboLayout,before.superchargerType,before.inductionRace=nil,nil,nil end
            end
        end
        local after=copySpec(before)
        for key,value in pairs(option.effect) do after[key]=value end
        local ok,reason=EngineEffects.shopRequired(after)
        -- third value: the part cannot be fitted (list marks it unsafe, apply refuses)
        if not ok then return option.title,reason,reason end
        local base=EngineEffects.curve(curves.stock,curves.limit,before,true)
        local modified=EngineEffects.curve(curves.stock,curves.limit,after,true)
        local a,b=Effects.peaks({{torque=base}}),Effects.peaks({{torque=modified}})
        local peakRPM,peak=0,0
        for _,p in ipairs(modified) do if p[1]*p[2]>peak then peak=p[1]*p[2];peakRPM=p[1] end end
        local low=(EngineEffects.torque(curves.stock,3000,curves.limit,after,true)-EngineEffects.torque(curves.stock,3000,curves.limit,before,true))*Effects.NM_TO_LBFT
        return string.format('%s: %+.0f hp at %g rpm, %+.0f lb-ft at 3,000 rpm',option.title,b.hp-a.hp,peakRPM,low),
            string.format('%+.1f kW, %+.1f Nm peak torque; %g rpm limit. Gains include other fitted parts; race sliders rated at maximum.',b.kw-a.kw,b.nm-a.nm,EngineEffects.revLimit(curves.limit,after)),
            nil, b.hp - a.hp
    end
    local info=catalog.parts[name]
    if info then
        if info.kind=='aero' then
            return info.name,string.format('%.1f kg maximum at 200 km/h; +%.3f CdA; lift-to-drag %.1f. Always rated at maximum.',
                info.maxDownforceKG,info.extraCdA,info.liftDrag)
        end
        if info.kind=='brake' then
            return string.format('%s: %+d %% brake torque, %s pads',info.name,math.floor((info.torqueScale-1)*100+.5),info.pads),
                string.format('%+d %% brake cooling; pads are never downgraded.%s',math.floor((info.coolingScale-1)*100+.5),
                    info.level=='race' and not info.native and ' Unlocks Brake Power tuning (50-150 %), rated at 150 %.' or '')
        end
        if info.kind~='tyre' then return info.name end
        if info.native then
            return info.name,string.format('Native tyre: nominal width %g mm; physical contact width %g mm. Automation compound donor %s (%s axle).',
                info.nominalWidthMM,info.physicsWidthMM,tostring(info.donorModel),tostring(info.donorAxle))
        end
        return info.name,string.format('Automation coefficients from %s (%s axle). Width %g mm.',tostring(info.donorModel),tostring(info.donorAxle),info.widthMM or 0)
    end
end
U.summary=function(vehID)
    local r=rawget(_G,'raceprepRatings')
    local live=r and r.getLiveCarData and r.getLiveCarData(vehID)
    if live then return Effects.summary(live) end
    local st=r and r.getCarData and r.getCarData(vehID)
    if not st then return nil end
    local summary=Effects.summary(st)
    if not summary then return nil end
    summary.reference=true
    summary.massKG=st.mass+40
    summary.massLB=summary.massKG*Effects.KG_TO_LB
    return summary
end

local PartsRules = require("ge/extensions/raceprep/partsRules")

U.GROUPS = {
    { key = "engine", label = "Engine" },
    { key = "conversion", label = "Engine conversion" },
    { key = "drivetrain", label = "Drivetrain" },
    { key = "suspension", label = "Suspension and brakes" },
    { key = "tyres", label = "Wheels and tyres" },
    { key = "aero", label = "Aero" },
    { key = "nitrous", label = "Nitrous" },
}

U.history = {} -- undo stack: {vehID, tree, before = rating entry, label}
U.lastChange = nil -- {vehID, label, before = {class, pi}}

local function jbeamIO()
    local ok, io = pcall(require, "jbeam/io")
    return ok and io or nil
end

local function vehData(vehID)
    return core_vehicle_manager and core_vehicle_manager.getVehicleData(vehID) or nil
end

-- Native bodies have their own holder slot and fixed part-level scale.
-- The Automation helper only receives Automation catalogue/vehicle data.
local function bodyAdapter(d)
    local native=require('ge/extensions/raceprep/nativeWeight')
    return native.native(d,catalog) and native or require('ge/extensions/raceprep/weight')
end
U.bodyRows=function(vehID,mass)
    local d=vehData(vehID);if not d then return {} end
    return bodyAdapter(d).rows(d,catalog,mass)
end
U.bodyProblem=function(d) return bodyAdapter(d).problem(d,catalog) end
U.bodyStage=function(vehID,key) return bodyAdapter(vehData(vehID)).find(key) end

-- slot definitions of an installed part: {id, def (for compatibility), default, description}
local function slotsOf(vdata, partName)
    local data = vdata and vdata.activePartsData and vdata.activePartsData[partName]
    local out = {}
    if not data then return out end
    if data.slots2 then
        for _, s in ipairs(data.slots2) do
            table.insert(out, { id = s.name or s.type, def = s, default = s.default, description = s.description,
                core = s.coreSlot == true })
        end
    elseif data.slots then
        for i, s in ipairs(data.slots) do
            if i > 1 and type(s) == "table" and s[1] then
                local opts = type(s[4]) == "table" and s[4] or {}
                table.insert(out, { id = s[1], def = { type = s[1] }, default = s[2], description = s[3],
                    core = opts.coreSlot == true })
            end
        end
    end
    return out
end

-- Engine balancing parts change the engine's inertia by a fixed amount
-- ("$+inertia": -0.04 / -0.07) or a factor ("$*inertia"). On light engines
-- that leaves zero or negative inertia and the engine cannot turn (TATA Dot:
-- 0.06997 - 0.07; Miota R, Giselle C, Hartis: below 0.04). Such options are
-- marked unsafe and cannot be applied.
U.MIN_INERTIA = 0.015
U.MIN_INERTIA_SHARE = 0.25

local function inertiaMod(part)
    local e = type(part) == "table" and part.mainEngine
    if type(e) ~= "table" then return nil end
    local add, mult = tonumber(e["$+inertia"]), e["$*inertia"]
    if add then return { add = add } end
    if mult ~= nil then return { mult = tonumber(mult) or 1 } end -- variable: its default (1)
    return nil
end

local function engineInertia(d)
    local e = d and d.vdata and d.vdata.mainEngine
    return type(e) == "table" and tonumber(e.inertia) or nil
end

--- would this part leave the engine too light to run? reason or nil
U.inertiaProblem = function(current, currentPart, optionPart)
    current = tonumber(current)
    local now, opt = inertiaMod(currentPart), inertiaMod(optionPart)
    if not current or not opt then return nil end
    local base = current
    if now and now.add then base = current - now.add elseif now and now.mult and now.mult ~= 0 then base = current / now.mult end
    local result = opt.add and (base + opt.add) or (base * (opt.mult or 1))
    if result < math.max(U.MIN_INERTIA, U.MIN_INERTIA_SHARE * base) then
        return "won't run on this engine (too light)"
    end
end

--- upgradeable slots of a car: list of {group, path (slot ids from the
--- root), slot, title, current, options = {{name, title, unsafe}}}
U.list = function(vehID, getCompatible, partInfo, getPartData)
    local d = vehData(vehID)
    if not d or not d.config or not d.config.partsTree or not d.vdata then return {} end
    local io = jbeamIO()
    local available = partInfo or (io and io.getAvailableParts and io.getAvailableParts(d.ioCtx)) or {}
    getCompatible = getCompatible or function(slotDef)
        if not io then return {} end
        local ok, names = pcall(io.getCompatiblePartNamesForSlot, d.ioCtx, slotDef)
        return ok and names or {}
    end
    getPartData = getPartData or function(name)
        if not io or not io.getPart then return nil end
        local ok, part = pcall(io.getPart, d.ioCtx, name)
        return ok and part or nil
    end
    local inertia = engineInertia(d)
    local function title(name)
        local info = available[name]
        return type(info) == "table" and (info.description or info.name) or name
    end
    local camso,nativeEngine=false,false
    for _,p in pairs(d.vdata.powertrain or {}) do
        local kind=p.type or p[1]
        if kind=='camsoEngine' then camso=true end
        if kind=='combustionEngine' or kind=='electricMotor' then nativeEngine=true end
    end
    local model=d.vdata.model or d.config.model
    local out = {}
    -- Automation donors can use BeamNG's combustionEngine runtime too. They
    -- keep their copied donor upgrades; the vanilla-only RP whitelist would
    -- otherwise hide every one of those namespaced parts after the swap.
    local convertedEngine=false
    for _,name in pairs(d.vdata.activeParts or {}) do
        if type(name)=='string' and name:match('^rp_swap_.*_engine$') then
            local option=Conversions.option(model,name)
            if option and not option.stock then convertedEngine=true;break end
        end
    end
    local nativeShop=not camso and nativeEngine and not convertedEngine
    if not camso and not convertedEngine then
        for _,info in pairs(catalog.parts) do if info.native==true and info.model==model then nativeShop=true break end end
    end
    local nativeTyreRows={}
    if not camso and not convertedEngine and catalog.nativeTyres then
        local native=require('ge/extensions/raceprep/nativeTyres')
        if native.enabled(catalog,model,d.vdata) then
            nativeShop=true
            for _,row in ipairs(native.rows(catalog,model,d.config.partsTree)) do
                out[#out+1]=row
                nativeTyreRows[table.concat(row.path,'/')]=row
            end
        end
    end
    local function walk(node, path)
        for _, slot in ipairs(slotsOf(d.vdata, node.chosenPartName)) do
            local child = node.children and node.children[slot.id]
            local childPath = {}
            for i, p in ipairs(path) do childPath[i] = p end
            table.insert(childPath, slot.id)
            if child then
                local group = PartsRules.groupOf(slot.id,nativeShop)
                local model=d.vdata.model or d.config.model
                local conversion=slot.id=='Camso_Engine' and Conversions.info(model)
                local dtConversion=slot.id=='Camso_TransferCase' and DrivetrainConversions.info(model)
                local currentDrive=DrivetrainConversions.currentLayout(model,d.config.partsTree,d.vdata.activeParts)
                if conversion then group='conversion' end
                if Conversions.info(model) and (slot.id=='Camso_engine_structure' or slot.id=='Camso_engine_mesh') then group=nil end
                if currentDrive=='RWD' and slot.id=='Camso_differential_front' then group=nil end
                if currentDrive=='FWD' and slot.id=='Camso_differential_rear' then group=nil end
                local engineInfo=camso and U.engineInfo(model,d.vdata.activeParts)
                local hubSlot=engineInfo and engineInfo.hubSlot or 'camso_tuning_parameters_engine'
                local engineSlot=false
                for _,id in pairs(engineInfo and engineInfo.slots or {}) do if id==slot.id then engineSlot=true end end
                if camso and group=='engine' and not engineSlot and slot.id~=hubSlot then group=nil end
                if group=='aero' and slot.id~='camso_tuning_parameters' and not nativeShop then group=nil end
                if group=='body' then group=nil end -- Upgrades > Body (raceprep/weight)
                local tyreRow=nativeTyreRows[table.concat(childPath,'/')]
                if nativeShop and group=='tyres' and tyreRow then
                    -- Keep compound/width RP rows, with compatible factory choices
                    -- on the same slot rather than duplicating or hiding the row.
                    local listed={}
                    for _,option in ipairs(tyreRow.options) do listed[option.name]=true end
                    local factoryOptions={}
                    for _,name in ipairs(getCompatible(slot.def) or {}) do
                        if not listed[name] and not name:match('^rp_') then
                            factoryOptions[#factoryOptions+1]={name=name,title=title(name)}
                            listed[name]=true
                        end
                    end
                    table.sort(factoryOptions,function(a,b) return tostring(a.title)<tostring(b.title) end)
                    for _,option in ipairs(factoryOptions) do tyreRow.options[#tyreRow.options+1]=option end
                    if not slot.core and (slot.default==nil or slot.default=='') and not listed[''] then
                        table.insert(tyreRow.options,1,{name='',title='None'})
                    end
                    group=nil
                end
                if group then
                    local names = getCompatible(slot.def) or {}
                    local options = {}
                    local currentPart = inertia and getPartData(child.chosenPartName)
                    for _, n in ipairs(names) do
                        local keep=true
                        if nativeShop then
                            -- Factory hardware comes from BeamNG's compatibility
                            -- resolver. RP copies remain limited to this model and
                            -- fitted source; do not borrow another car's variants.
                            local fitted=catalog.parts[child.chosenPartName or '']
                            local source=fitted and fitted.native and fitted.model==model and fitted.stockPart or child.chosenPartName
                            local candidate=catalog.parts[n]
                            keep=not n:match('^rp_') or n==child.chosenPartName or
                                (candidate and candidate.native==true and candidate.model==model and
                                 candidate.stockPart==source and candidate.slotType==slot.id)
                        end
                        if conversion then keep=Conversions.option(model,n)~=nil end
                        if dtConversion then keep=DrivetrainConversions.option(model,n)~=nil end
                        if slot.id==hubSlot and camso then keep=engineInfo and n==engineInfo.hub end
                        if camso and group=='engine' and engineSlot then keep=engineInfo.parts[n]~=nil or n==slot.default or n==child.chosenPartName end
                        if slot.id=='camso_tuning_parameters' then keep=catalog.parts[n] and catalog.parts[n].kind=='aero' end
                        if keep then
                        local effect,tip,blocked,power=U.partEffect(vehID,n)
                        local o = { name = n, title = effect or title(n), tooltip=tip, power=power,
                            rule = U.ruleItem(model, engineInfo, n, group) } -- race-rule caps (raceprep/upgradeRules)
                        -- BeamNG cars: a factory engine part other than the spawned config's
                        if not o.rule and group == 'engine' and not camso and PartsRules.factoryPart then
                            local stock = PartsRules.factoryPart(vehID, slot.id)
                            if stock ~= nil and n ~= stock then o.rule = PartsRules.factoryRuleItem(n, o.title) end
                        end
                        if conversion then o.tooltip=Conversions.tooltip(model,n) or o.tooltip end
                        if conversion and n==conversion.stockEngine then o.title='Stock engine';o.tooltip='Restore this car’s original engine and engine block mass.' end
                        if dtConversion and n==dtConversion.stockTransferCase then
                            o.title='Stock drivetrain ('..tostring(dtConversion.stockDrive)..')'
                            o.tooltip=string.format('Restore this car’s original %s drivetrain layout and differentials (%.2f:1 final drive).',tostring(dtConversion.stockDrive),tonumber(dtConversion.stockFinalDrive) or 0)
                        end
                        if inertia and n ~= child.chosenPartName and not conversion and not dtConversion then
                            o.unsafe = U.inertiaProblem(inertia, currentPart, getPartData(n))
                        end
                        if blocked and n ~= child.chosenPartName then o.unsafe = o.unsafe or blocked end
                        table.insert(options, o)
                        end
                    end
                    -- the fitted part is always an option, so its dropdown never shows blank
                    local fitted = child.chosenPartName or ""
                    local listed = fitted == ""
                    for _, o in ipairs(options) do if o.name == fitted then listed = true end end
                    if not listed and not (catalog.parts[fitted] and catalog.parts[fitted].kind == "bodyHolder") then
                        table.insert(options, { name = fitted, title = title(fitted) })
                    end
                    -- optional slots (empty default) can be emptied again: "None"
                    local drivenDiff=slot.id=='Camso_differential_front' or slot.id=='Camso_differential_rear'
                    local optional=not conversion and not dtConversion and not drivenDiff and (slot.default==nil or slot.default=="") and group~="nitrous" and slot.id~=hubSlot and slot.id~="camso_tuning_parameters"
                    if optional and not slot.core then table.insert(options, 1, { name = "", title = "None" }) end
                    if (group == "nitrous" or (not nativeShop and (slot.id==hubSlot or slot.id=="camso_tuning_parameters"))) and not slot.core then
                        local stockTitle=group=="nitrous" and "None" or "Stock"
                        local stockTip
                        if slot.id==hubSlot and camso then
                            stockTitle='No extra engine slots'
                            stockTip='Fit Engine upgrade slots to add exhaust, cam, displacement, forced-induction and cooler choices.'
                        elseif slot.id=='camso_tuning_parameters' then
                            local model=d.config.model or d.vdata.model
                            for _,part in pairs(U.modelParts(catalog,model)) do
                                if part.kind=='aero' and part.model==model then
                                    local kg=part.stockFrontKG+part.stockRearKG
                                    stockTitle=string.format('Stock: %.0f lbs %s at 200 km/h, +0 N drag',math.abs(kg)*Effects.KG_TO_LB,kg<0 and 'lift' or 'downforce')
                                    stockTip=string.format('%.1f kg signed downforce at 200 km/h. Original exported aero.',kg)
                                    break
                                end
                            end
                        end
                        table.insert(options, 1, { name = "", title=stockTitle,tooltip=stockTip })
                    end
                    -- deterministic option order: Stock -> Sport -> Race.
                    -- within a tier, engine parts sort weakest to strongest
                    -- (o.power is the dyno delta partEffect computed), then by
                    -- title so same-type hardware stays adjacent
                    local fittedName=child.chosenPartName or ''
                    local fittedInfo=catalog.parts[fittedName]
                    local stockName=fittedInfo and fittedInfo.stockPart
                    local tyreRank={stock=0,sport=1,semi_slick=2,race_supersoft=3,race_soft=4,race_medium=5,race_hard=6}
                    local function tierOf(o)
                        if o.name=='' then return -1 end
                        if o.name==slot.default or o.name==stockName then return 0 end
                        local cp=catalog.parts[o.name]
                        if cp then
                            if cp.kind=='tyre' then return tyreRank[cp.compound] or 1.5 end
                            if cp.kind=='brake' then return cp.level=='race' and 2 or cp.level=='sport' and 1 or 1.5 end
                            if cp.kind=='aero' then return ({street=1,sport=2,race=3})[cp.kit] or 1.5 end
                            if cp.kind=='bodyHolder' then return 0 end
                        end
                        local ep=camso and engineInfo and engineInfo.parts[o.name]
                        if ep and ep.effect and ep.effect.inductionRace~=nil then return ep.effect.inductionRace and 2 or 1 end
                        local head=tostring(o.title):lower()
                        if head:match('^stock') or head:match('^standard') or head:match('^factory') then return 0 end
                        if head:match('%( *race') or head:match('^race') or head:match('^racing') or head:match('competition') or head:match('^ultra') then return 2 end
                        if head:match('^sport') or head:match('^street') or head:match('lightened') then return 1 end
                        if ep then
                            local ln=o.name:lower()
                            if ln:match('race') and (ln:match('race$') or ln:match('race[_-]')) then return 2 end
                            if ln:match('stage2') then return 2 end
                            if ln:match('sport$') or ln:match('sport[_-]') or ln:match('stage1') then return 1 end
                        end
                        return 1.5
                    end
                    table.sort(options, function(a, b)
                        if conversion and (a.name==conversion.stockEngine)~=(b.name==conversion.stockEngine) then return a.name==conversion.stockEngine end
                        if dtConversion and (a.name==dtConversion.stockTransferCase)~=(b.name==dtConversion.stockTransferCase) then return a.name==dtConversion.stockTransferCase end
                        if slot.id=='camso_tuning_parameters' then
                            local order={street=1,sport=2,race=3}
                            local pa,pb=catalog.parts[a.name],catalog.parts[b.name]
                            local la,lb=(pa and order[pa.kit] or 0),(pb and order[pb.kit] or 0)
                            if la~=lb then return la<lb end
                            return tostring(a.title) < tostring(b.title)
                        end
                        if (a.name == "") ~= (b.name == "") then return a.name == "" end
                        local ta,tb=tierOf(a),tierOf(b)
                        if ta~=tb then return ta<tb end
                        local pa,pb=a.power,b.power
                        if pa and pb and pa~=pb then return pa<pb end
                        if (pa~=nil) ~= (pb~=nil) then return pa~=nil end
                        return tostring(a.title) < tostring(b.title)
                    end)
                    -- the body holder is stock aero
                    local holder = catalog.parts[child.chosenPartName or ""] and catalog.parts[child.chosenPartName].kind == "bodyHolder"
                    if #options >= 2 then
                        local fittedOpt=dtConversion and DrivetrainConversions.option(model,child.chosenPartName)
                        table.insert(out, { group = group, path = childPath, slot = slot.id,
                            title = conversion and 'Engine conversion' or dtConversion and 'Drivetrain conversion' or slot.id==hubSlot and camso and "Engine upgrades" or slot.id=="camso_tuning_parameters" and "Aero kit" or slot.description or slot.id, current = holder and "" or child.chosenPartName or "",
                            currentTitle = (holder or (child.chosenPartName or "") == "") and "None" or (fittedOpt and fittedOpt.title) or title(child.chosenPartName),
                            options = options })
                    end
                end
                if child.chosenPartName and child.chosenPartName ~= "" then
                    walk(child, childPath)
                end
            end
        end
    end
    walk(d.config.partsTree, {})
    -- engine rows in a natural order, the rest alphabetical
    local engineInfo=camso and U.engineInfo(d.vdata.model or d.config.model,d.vdata.activeParts)
    local rank={Camso_TransferCase=0}
    for i,kind in ipairs({'intake','exhaust','ecu','cam','forged','displacement','flywheel','induction','intercooler','oilcooler','radiator'}) do
        local slot=engineInfo and engineInfo.slots and engineInfo.slots[kind]
        if slot then rank[slot]=i end
    end
    table.sort(out, function(a, b)
        local ra,rb=rank[a.slot] or 100,rank[b.slot] or 100
        if ra~=rb then return ra<rb end
        return tostring(a.title) < tostring(b.title)
    end)
    return out
end

local function copyTree(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copyTree(v) end
    return out
end

--- a copy of the parts tree with one slot changed (its own sub-slots reset to
--- the new part's defaults; Camso_Transmission preserves Camso_TransferCase)
U.changedTree = function(tree, path, partName)
    local newTree = copyTree(tree)
    local node = newTree
    for _, id in ipairs(path) do
        node = node.children and node.children[id]
        if not node then return nil end
    end
    local info=catalog.parts[partName]
    if info and info.native==true and info.kind=='brake' and info.padSlots then
        -- Generated native brakes keep their original child slot types. Carry
        -- factory pad choices up to the stage minimum, preserving better pads.
        local children=node.children or {}
        for _,pad in ipairs(info.padSlots) do
            local old=children[pad.id]
            local current=old and old.chosenPartName
            local selected=pad.default
            if current and current~='' then selected=pad.choices[current];if not selected then return nil end end
            local child=old or {id=pad.id,children={}}
            child.chosenPartName=selected;children[pad.id]=child
        end
        node.children=children
    else
        node.children = {}
    end
    node.chosenPartName = partName
    if path and path[#path] == "Camso_Transmission" then
        newTree = DrivetrainConversions.carry(tree, newTree)
    end
    return newTree
end

local function findSlot(node,slot)
    for id,child in pairs(node.children or {}) do
        if id==slot then return child end
        local found=findSlot(child,slot)
        if found then return found end
    end
end

--- differential devices a parts tree actually has, by powertrain device name.
--- frontDiff / rearDiff exist when the axle's Camso_differential_* slot is
--- filled; a centre device named transferCase exists when both axles are
--- driven (stock AWD transfer cases and generated ones alike)
local function diffDevicesInTree(tree)
    local front=findSlot(tree,'Camso_differential_front')
    local rear=findSlot(tree,'Camso_differential_rear')
    local f=front and (front.chosenPartName or '')~=''
    local r=rear and (rear.chosenPartName or '')~=''
    return {frontDiff=f,rearDiff=r,transferCase=f and r}
end
U.packageSpec=function(vehID,number)
    local curves=U.engineCurves(vehID)
    if not curves or not curves.spec then return nil,'No compatible engine package data.' end
    local spec=copySpec(curves.spec)
    spec.intake,spec.exhaust,spec.ecu,spec.cam,spec.forged,spec.displacement=nil,nil,nil,nil,nil,nil
    -- 0 = stock engine: every package part removed (forced induction and coolers stay)
    for kind,level in pairs(number==0 and {} or assert(EngineEffects.PACKAGES[number])) do spec[kind]=level end
    if spec.induction=='turbo_large' or spec.induction=='supercharger_race' or spec.induction=='stock_upgrade' then spec.forged=true end
    return spec,curves
end
--- is this package (0 = stock engine) what the engine has now?
U.packageFitted=function(vehID,number)
    local curves=U.engineCurves(vehID)
    if not curves or not curves.spec then return false end
    local want=number==0 and {} or EngineEffects.PACKAGES[number] or {}
    for _,kind in ipairs({'intake','exhaust','ecu','cam','forged','displacement'}) do
        if (curves.spec[kind] or nil)~=(want[kind] or nil) then return false end
    end
    return true
end
U.packageEffect=function(vehID,number)
    local spec,curves=U.packageSpec(vehID,number)
    if not spec then return (number==0 and 'Stock engine' or 'Stage '..number)..': reading dyno...' end
    if number==0 then return 'Stock engine' end
    local changed=EngineEffects.curve(curves.stock,curves.limit,spec,true)
    local base=Effects.peaks({{torque=curves.stock}})
    local total=Effects.peaks({{torque=changed}})
    return string.format('Stage %d: %+.0f hp, %+.0f lb-ft',number,total.hp-base.hp,total.lbft-base.lbft)
end
-- the jbeam default of a slot among the car's active parts ('' if optional)
local function slotDefault(vdata,slotId)
    for partName in pairs(vdata and vdata.activePartsData or {}) do
        for _,s in ipairs(slotsOf(vdata,partName)) do if s.id==slotId then return s.default or '' end end
    end
end
U.slotDefault=slotDefault
U.applyPackage=function(vehID,number,before)
    local d=vehData(vehID)
    local spec,curves=U.packageSpec(vehID,number)
    if not spec then return false,curves end
    local okSpec,why=EngineEffects.shopRequired(spec)
    if not okSpec then return false,why end
    local info=curves.info
    local tree=copyTree(d.config.partsTree)
    local hub=findSlot(tree,info.hubSlot or 'camso_tuning_parameters_engine')
    if not hub then return false,'No compatible engine upgrade slot.' end
    if hub.chosenPartName~=info.hub then hub.chosenPartName=info.hub;hub.children={} end
    for _,kind in ipairs({'intake','exhaust','ecu','cam','forged','displacement'}) do
        local slot=info.slots[kind]
        -- not in this package: the slot's stock part. The car's own intake,
        -- engine management and internals slots are core slots whose stock
        -- part is their default; '' emptied them (Stock engine left the car
        -- without an intake / ECU and the dropdowns blank). Race Prep's extra
        -- slots default to empty.
        local target=slotDefault(d.vdata,slot) or (kind=='forged' and slot) or ''
        if spec[kind] then
            local candidates={}
            for name,p in pairs(info.parts) do if p.effect[kind]==spec[kind] then candidates[#candidates+1]=name end end
            table.sort(candidates)
            target=candidates[#candidates]
            if not target then return false,'Missing '..kind..' part for this package.' end
        end
        local node=findSlot(tree,slot)
        if not node then
            if kind=='intake' or kind=='ecu' or kind=='forged' then return false,'Missing native '..kind..' slot.' end
            hub.children[slot]={chosenPartName=target,children={}}
        else node.chosenPartName=target;node.children={} end
    end
    local pm=extensions.core_vehicle_partmgmt
    local label=number==0 and 'Stock engine parts' or 'Stage '..number..' engine package'
    table.insert(U.history,{vehID=vehID,tree=copyTree(d.config.partsTree),vars=copyTree(d.config.vars or {}),label=label})
    while #U.history>20 do table.remove(U.history,1) end
    U.lastChange={vehID=vehID,label=label,before=before and {class=before.class,pi=before.pi}}
    pm.setPartsTreeConfig(tree,true)
    return true
end

---------------------------------------------------------------- tyre compounds
-- Race slick compounds (1.8.5): grip from Automation's Soft / Medium / Hard
-- Race tyres, wear and temperature window from Kagoni Tyre Simulation's
-- matching preset (the add-on keeps KTS on the fitted compound). KTS has one
-- slick compound per car, so a slick compound is fitted to both axles.
U.COMPOUNDS = { "stock", "sport", "semi_slick", "race_supersoft", "race_soft", "race_medium", "race_hard" }
U.COMPOUND_LABELS = { stock = "Stock", sport = "Sport", semi_slick = "Semi-slick",
    race_supersoft = "Race slick - Super Soft", race_soft = "Race slick - Soft",
    race_medium = "Race slick - Medium", race_hard = "Race slick - Hard" }
U.SLICKS = { "supersoft", "soft", "medium", "hard" }
U.SLICK_LABELS = { supersoft = "Super Soft", soft = "Soft", medium = "Medium", hard = "Hard" }

--- slick compound id ("soft") of a tyre compound ("race_soft"), else nil
U.slickOf = function(compound)
    return type(compound) == "string" and compound:match("^race_(%a+)$") or nil
end

local function findSlotNode(node, slot)
    for id, child in pairs(node and node.children or {}) do
        if id == slot then return child end
        local found = findSlotNode(child, slot)
        if found then return found end
    end
end

--- fitted tyres: {front = {part, compound}, rear = ...} (compound of a stock
--- tyre = the export's own, e.g. "race_soft" or "sport"); nil if not an upgradeable car
U.fittedTyres = function(vehID)
    local d = vehData(vehID)
    local tree = d and d.config and d.config.partsTree
    local model = d and d.vdata and (d.vdata.model or d.config.model)
    if not tree or not model then return nil end
    if catalog.nativeTyres then
        local native=require('ge/extensions/raceprep/nativeTyres')
        if native.enabled(catalog,model,d.vdata) then
            local out={}
            for _,row in ipairs(native.rows(catalog,model,tree)) do out[row.axle]=row.fitted end
            return next(out) and out or nil
        end
    end
    local out = nil
    for _, axle in ipairs({ "front", "rear" }) do
        local stock = catalog.stocks and catalog.stocks[model .. "/" .. axle]
        local node = findSlotNode(tree, "Camso_wheels_" .. axle)
        if stock and node then
            local info = catalog.parts[node.chosenPartName]
            local compound = info and info.kind == "tyre" and info.compound or "stock"
            if compound == "stock" then compound = stock.compound end
            out = out or {}
            out[axle] = { part = node.chosenPartName, compound = compound, offsetMM = info and info.kind == "tyre" and info.offsetMM or 0 }
        end
    end
    return out
end

--- the KTS tyre type for an Automation car ("standard", "sport", "semi_slick",
--- "race"), from its fitted tyres; nil for native cars and unknown compounds.
--- BeamNG 0.39 hides part titles from KTS, so it detects every Automation car
--- (Camso_wheels_*) as Standard; Race Prep tells it the real type. With
--- different axles the grippier one decides (as for the slick grade).
local KTS_RANK = { standard = 1, sport = 2, semi_slick = 3, race = 4 }
U.ktsProfile = function(vehID)
    local d = vehData(vehID)
    local model = d and d.vdata and (d.vdata.model or d.config.model)
    if catalog.nativeTyres and model and require('ge/extensions/raceprep/nativeTyres').enabled(catalog, model, d.vdata) then return nil end
    local tyres = U.fittedTyres(vehID)
    local best = nil
    for _, axle in ipairs({ "front", "rear" }) do
        local compound = tyres and tyres[axle] and tyres[axle].compound
        local profile = compound and (compound:match("^race") and "race" or compound)
        if profile and KTS_RANK[profile] and (not best or KTS_RANK[profile] > KTS_RANK[best]) then best = profile end
    end
    return best
end

-- Native configs may share a model but have different tyre sizes and slots.
-- Keep the original model/axle catalogue path for Automation.
U.tyreStock=function(vehID,axle)
    local d=vehData(vehID)
    local model=d and d.vdata and (d.vdata.model or d.config.model)
    if not model then return nil end
    if catalog.nativeTyres then
        local native=require('ge/extensions/raceprep/nativeTyres')
        if native.enabled(catalog,model,d.vdata) then
            for _,row in ipairs(native.rows(catalog,model,d.config.partsTree)) do
                if row.axle==axle then return row.nativeStock end
            end
            return nil
        end
    end
    return catalog.stocks and catalog.stocks[model..'/'..axle]
end

--- the KTS slick preset for this car ("soft"...), from its fitted slicks; nil without slicks
U.slickPreset = function(vehID)
    local tyres = U.fittedTyres(vehID)
    if not tyres then return nil end
    -- one preset per car: the rear decides when the axles differ
    return U.slickOf(tyres.rear and tyres.rear.compound) or U.slickOf(tyres.front and tyres.front.compound)
end

--- race rule: is this slick compound allowed? (rules.slickCompounds[id] == false bans it)
U.slickAllowed = function(rules, slick)
    local allowed = type(rules) == "table" and type(rules.slickCompounds) == "table" and rules.slickCompounds or {}
    return slick == nil or allowed[slick] ~= false
end

--- reason the fitted tyres break the race's compound rule, else nil
U.compoundViolation = function(vehID, rules)
    local tyres = U.fittedTyres(vehID)
    for _, axle in ipairs({ "front", "rear" }) do
        if tyres and tyres[axle] and tyres[axle].unknownSlickGrade then
            for _,allowed in pairs(type(rules)=='table' and type(rules.slickCompounds)=='table' and rules.slickCompounds or {}) do
                if allowed==false then return 'Factory slick grade is unspecified: fit an allowed Race Prep slick compound.' end
            end
        end
        local slick = tyres and tyres[axle] and U.slickOf(tyres[axle].compound)
        if slick and not U.slickAllowed(rules, slick) then
            return "Race slick " .. U.SLICK_LABELS[slick] .. " is not allowed in this race"
        end
    end
end

--- several slots at once, one rebuild: changes = {{entry, partName}, ...}
U.applyMany = function(vehID, changes, label, before)
    local d = vehData(vehID)
    local pm = extensions and extensions.core_vehicle_partmgmt
    if not d or not pm or not pm.setPartsTreeConfig or #changes == 0 then return false end
    local tree = d.config.partsTree
    local model = d.config.model or d.vdata.model
    local vars,restoreVars,diffSnapshot
    for _,c in ipairs(changes) do
        if c[1].group=='conversion' and #changes~=1 then return false,'Apply the engine conversion separately, then choose its upgrades.' end
        if c[1].slot=='Camso_TransferCase' and DrivetrainConversions.info(model) and #changes~=1 then
            return false,'Apply the drivetrain conversion separately, then choose its differential or gearing upgrades.'
        end
    end
    for _, c in ipairs(changes) do
        if c[1].group=='conversion' then
            local why
            tree,why,vars,restoreVars=Conversions.change(tree,c[1].path,c[2],model,d.config.vars)
            if not tree then return false,why end
        elseif c[1].slot=='Camso_TransferCase' and DrivetrainConversions.info(model) then
            local why
            tree,why,vars,restoreVars=DrivetrainConversions.change(tree,c[1].path,c[2],model,d.config.vars)
            if not tree then return false,why end
            local rt=rawget(_G,'bjiRacePrep')
            if rt and rt.diffSettings then
                -- keep settings for differential devices that still exist
                -- (RWD -> AWD keeps rearDiff); the pre-conversion set is
                -- deep-copied into the undo entry so it can be restored
                diffSnapshot=copyTree(rt.diffSettings[vehID] or {})
                local present=diffDevicesInTree(tree)
                local kept={}
                for name,s in pairs(rt.diffSettings[vehID] or {}) do
                    if present[name] then kept[name]=s end
                end
                rt.diffSettings[vehID]=kept
            end
        else tree = U.changedTree(tree, c[1].path, c[2]) end
        if not tree then return false end
        -- aero kits and the body holder share a slot: keep the fitted body stage
        if c[1].slot == "camso_tuning_parameters" then
            tree = require("ge/extensions/raceprep/weight").carry(d.config.partsTree, tree, catalog, model)
        end
    end
    table.insert(U.history, { vehID = vehID, tree = copyTree(d.config.partsTree), vars = restoreVars or copyTree(d.config.vars or {}), label = label, diffs = diffSnapshot })
    while #U.history > 20 do table.remove(U.history, 1) end
    U.lastChange = { vehID = vehID, label = label, before = before and { class = before.class, pi = before.pi } or nil }
    if vars and pm.setConfigVars then pm.setConfigVars(vars,false) end
    pm.setPartsTreeConfig(tree, true)
    return true
end

--- fit a weight reduction stage (Upgrades > Body): node weight is read when
--- the car loads, so the variable is set with a reload (raceprep/weight)
U.applyWeight = function(vehID, key, before)
    local d = vehData(vehID)
    local W = bodyAdapter(d)
    local pm = extensions and extensions.core_vehicle_partmgmt
    local stage = W.find(key)
    if not d or not pm or not pm.setPartsTreeConfig then return false, "Reading car data." end
    if not stage then return false, "Unknown body stage." end
    local tree, why = W.applyTree(d.config.partsTree, catalog, d.config.model or d.vdata.model, key)
    if not tree then return false, why end
    table.insert(U.history, { vehID = vehID, tree = copyTree(d.config.partsTree), vars = copyTree(d.config.vars or {}), label = stage.label })
    while #U.history > 20 do table.remove(U.history, 1) end
    U.lastChange = { vehID = vehID, label = "Body: " .. stage.label, before = before and { class = before.class, pi = before.pi } or nil }
    -- a value left in the config (e.g. Automation's own slider) would override the part
    if W.VAR and pm.setConfigVars then pm.setConfigVars({ [W.VAR] = stage.scale }, false) end
    pm.setPartsTreeConfig(tree, true)
    return true
end

--------------------------------------------------------- race rules for upgrades
-- What a part is for the upgrade caps (raceprep/upgradeRules): engine level,
-- forced induction, cooling, conversions, tyres, body stage, brakes, aero,
-- nitrous. nil = not an upgrade the caps cover (factory and tuning parts).
local UpgradeRules = require("ge/extensions/raceprep/upgradeRules")
U.ruleItem = function(model, engine, name, group)
    if not name or name == "" then return nil end
    local conversion = model and Conversions.option(model, name)
    if conversion then return not conversion.stock and { kind = "engineConversion", title = conversion.title } or nil end
    local dt = model and DrivetrainConversions.option(model, name)
    if dt then return not dt.stock and { kind = "drivetrainConversion", layout = dt.layout, title = dt.title } or nil end
    local ep = engine and engine.parts and engine.parts[name]
    if ep and type(ep.effect) == "table" then
        local e = ep.effect
        if e.induction then return { kind = "induction", factory = false, title = ep.title } end
        if e.radiator or e.intercooler or e.oilcooler then return { kind = "cooling", title = ep.title } end
        local rank = UpgradeRules.engineRank(e)
        return rank and { kind = "engine", rank = rank, title = ep.title } or nil
    end
    local info = catalog.parts[name]
    if info then
        if info.kind == "tyre" then return { kind = "tyre", compound = info.compound, offset = info.offsetMM or 0, title = info.name } end
        if info.kind == "brake" then return { kind = "brake", level = info.level, title = info.name } end
        if info.kind == "aero" then return { kind = "aero", title = info.name } end
        if info.kind == "body" then return { kind = "body", stage = info.stage, title = info.name } end
    end
    if group == "nitrous" then return { kind = "nitrous", title = name } end
    return nil
end

--- everything fitted to the car that the upgrade caps look at (ready check)
U.ruleFacts = function(vehID)
    local d = vehData(vehID)
    if not d or not d.vdata then return {} end
    local model = d.vdata.model or d.config.model
    local engine = model and U.engineInfo(model, d.vdata.activeParts)
    local out, induction = {}, false
    for slot, name in pairs(d.vdata.activeParts or {}) do
        -- tyres are read below per axle (a stock tyre has its own compound)
        local part = type(name) == "string" and catalog.parts[name]
        if type(name) == "string" and not (part and part.kind == "tyre") then
            local item = U.ruleItem(model, engine, name, PartsRules.groupOf(tostring(slot)))
            if item then
                if item.kind == "induction" then induction = true end
                out[#out + 1] = item
            end
        end
    end
    -- BeamNG cars: factory engine parts other than the spawned configuration's
    for _, item in ipairs(PartsRules.factoryRuleItems and PartsRules.factoryRuleItems(vehID) or {}) do out[#out + 1] = item end
    -- factory turbo / supercharger: counts against "no forced induction" only
    if engine and engine.stockForcedInduction and not induction then
        out[#out + 1] = { kind = "induction", factory = true, title = "Factory forced induction" }
    end
    for _, axle in ipairs({ "front", "rear" }) do
        local t = (U.fittedTyres(vehID) or {})[axle]
        if t then out[#out + 1] = { kind = "tyre", compound = t.compound, offset = t.offsetMM or 0, title = axle .. " tyres" } end
    end
    local layout = model and DrivetrainConversions.currentLayout(model, d.config.partsTree, d.vdata.activeParts)
    local dt = model and DrivetrainConversions.info(model)
    if dt and layout and dt.stockDrive and layout ~= dt.stockDrive then
        local seen = false
        for _, item in ipairs(out) do if item.kind == "drivetrainConversion" then seen = true end end
        if not seen then out[#out + 1] = { kind = "drivetrainConversion", layout = layout, title = layout .. " conversion" } end
    end
    return out
end

--- is the group allowed here? (free roam, or the race grid with rules allowing it)
U.allowed = function(group, rules, freeroam, onGrid)
    if group=='conversion' then group='engine' end
    if not freeroam and not onGrid then return false, "Upgrades: free roam, or a race grid that allows parts changes." end
    if onGrid and rules then
        if group=="aero" and rules.aero==false then return false,"Stock aero required for this race." end
        if group == "nitrous" and rules.nitrous == false then return false, "Nitrous is banned in this race." end
        local parts = type(rules.parts) == "table" and rules.parts or {}
        if group ~= "nitrous" and parts[group] == "stock" then return false, "Factory parts only in this race." end
    end
    return true
end

--- change one slot; respawns the car (rating recomputed)
U.apply = function(vehID, entry, partName, before)
    if entry.group=='conversion' then return U.applyMany(vehID,{{entry,partName}},'Engine conversion',before) end
    local d = vehData(vehID)
    local model = d and (d.config.model or d.vdata.model)
    if entry.slot=='Camso_TransferCase' and model and DrivetrainConversions.info(model) then
        return U.applyMany(vehID,{{entry,partName}},'Drivetrain conversion',before)
    end
    local pm = extensions and extensions.core_vehicle_partmgmt
    if not d or not pm or not pm.setPartsTreeConfig then return false end
    -- never fit a part the list marked unsafe (engine too light, missing
    -- forged internals, second charger on a forced-induction engine...)
    for _, o in ipairs(entry.options or {}) do
        if o.name == partName and o.unsafe then return false, o.unsafe end
    end
    local newTree = U.changedTree(d.config.partsTree, entry.path, partName)
    if not newTree then return false end
    -- aero kits and the body holder share a slot: keep the fitted body stage
    if entry.slot == "camso_tuning_parameters" then
        newTree = require("ge/extensions/raceprep/weight").carry(d.config.partsTree, newTree, catalog, d.config.model or d.vdata.model)
    end
    table.insert(U.history, { vehID = vehID, tree = copyTree(d.config.partsTree), vars=copyTree(d.config.vars or {}), label = entry.title })
    while #U.history > 20 do table.remove(U.history, 1) end
    local partTitle = partName == "" and "None" or partName
    for _, o in ipairs(entry.options or {}) do
        if o.name == partName then partTitle = tostring(o.title):gsub(":.*$", "") end
    end
    U.lastChange = { vehID = vehID, label = string.format("%s: %s", tostring(entry.title), partTitle),
        before = before and { class = before.class, pi = before.pi } or nil }
    pm.setPartsTreeConfig(newTree, true)
    return true
end

U.undo = function(vehID)
    local last = U.history[#U.history]
    local pm = extensions and extensions.core_vehicle_partmgmt
    if not last or last.vehID ~= vehID or not pm then return false end
    table.remove(U.history)
    U.lastChange = { vehID = vehID, label = "Undo: " .. tostring(last.label) }
    -- restore the differential settings saved with this change, for the
    -- devices the restored tree actually has; after the rebuild bjiRacePrep
    -- re-sends them (pendingReapply) and the new diff report prunes leftovers
    if last.diffs then
        local rt=rawget(_G,'bjiRacePrep')
        if rt and rt.diffSettings then
            local present=diffDevicesInTree(last.tree)
            local restored={}
            for name,s in pairs(last.diffs) do
                if present[name] then restored[name]=copyTree(s) end
            end
            rt.diffSettings[vehID]=restored
        end
    end
    if pm.setConfigVars and last.vars then pm.setConfigVars(last.vars,false) end
    pm.setPartsTreeConfig(last.tree, true)
    return true
end

--- give a saved setup the picture of the factory config it came from (or the
--- model's default), so the vehicle list shows which car it is
U.copyPreview = function(vehID, name)
    local d = vehData(vehID)
    local model = d and (d.config.model or d.vdata.model)
    local info = model and core_vehicles and core_vehicles.getModel and core_vehicles.getModel(model)
    if not info or not FS then return false end
    local configs = info.configs or {}
    local base = d.config.partConfigFilename and d.config.partConfigFilename:match("([^/\\]+)%.pc$")
    local from = configs[base]
    if not from or from["Config Type"] == "Custom" or base == name then from = configs[info.model and info.model.default_pc or ""] end
    local src = from and from.preview
    if type(src) ~= "string" or not src:find("/vehicles/" .. model .. "/", 1, true) or not FS:fileExists(src) then return false end
    local dst = string.format("/vehicles/%s/%s.%s", model, name, src:match("%.(%a+)$") or "jpg")
    if FS:fileExists(dst) then return false end -- never replace a picture the player made
    FS:copyFile(src, dst)
    return true, dst
end

--- save the car (parts and tuning) as a config of its own; it shows in the
--- vehicle list. name: file name without .pc
U.save = function(name)
    local pm = extensions and extensions.core_vehicle_partmgmt
    name = tostring(name or ""):gsub("[^%w%s%-_%(%)]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or not pm or not pm.saveLocal then return false, "Enter a name." end
    local ok, res = pcall(pm.saveLocal, name .. ".pc")
    if ok and res ~= false then
        local veh = be and be:getPlayerVehicle(0)
        local extra = ""
        if veh then
            -- the saved setup shows the original car's picture and its rating
            pcall(U.copyPreview, veh:getID(), name)
            local r = rawget(_G, "raceprepRatings")
            local rok, saved, e = pcall(function() return r and r.rememberSavedSetup(veh:getID(), name) end)
            if rok and saved and e then extra = string.format(" Rated %s %d.", e.class, e.pi) end
        end
        return true, "Saved as \"" .. name .. "\" (vehicle list)." .. extra
    end
    return false, "Could not save: " .. tostring(res)
end

return U
