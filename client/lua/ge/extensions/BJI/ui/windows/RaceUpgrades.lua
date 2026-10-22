-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Upgrades & tuning window (RacePrep add-on, Forza style): swap the parts
-- your car's export offers (Engine, Drivetrain, Suspension and brakes, Wheels
-- and tyres, Nitrous), tune it (every tuning slider the car has, e.g. RPM
-- limit; idle RPM comes with "Race Engine Management"), see the class / PI
-- change, undo, and save the result as a config of its own. Opened from the
-- "Race Prep" menu: in free roam, or on a race grid whose rules allow parts.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local upgrades = require("ge/extensions/raceprep/upgrades")
local tuningPolicy=require('ge/extensions/raceprep/tuningPolicy')
local engineGraph=require('ge/extensions/raceprep/engineGraph')

---@class BJIWindowRaceUpgrades : BJIWindow
local W = {
    name = "RaceUpgrades",
    minSize = ImVec2(560, 420),
    maxSize = ImVec2(1200, 1400),
    flags = { BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE },
    show = false,
}

local cache = { vehID = nil, vdata = nil, list = {} }
local pendingVars, varsFor = {}, nil
local saveName, saveMessage = "", nil
local message = nil

local function context()
    local sc = rawget(_G, "BJI_Scenario")
    local freeroam = sc and sc.isFreeroam and sc.isFreeroam() or false
    local race = sc and sc.TYPES and sc.get and sc.get(sc.TYPES.RACE_MULTI)
    local onGrid = race and race.state and race.STATES and race.state == race.STATES.GRID and
        race.isParticipant and race.isParticipant() and not (race.isReady and race.isReady()) or false
    local rt = rawget(_G, "bjiRacePrep")
    local rules = onGrid and rt and rt.getRules and rt.getRules(race.raceID) or nil
    return freeroam, onGrid, rules
end

local function currentVehicle()
    local v = rawget(_G, "BJI_Veh")
    return v and v.getCurrentVehicleOwn and v.getCurrentVehicleOwn() or nil
end

local function ratingOf(vehID)
    local rt = rawget(_G, "raceprepRatings")
    if rt and rt.getVehicle then
        local ok, entry, status = pcall(rt.getVehicle, vehID)
        if ok then return entry, status end
    end
end

local function badge(entry)
    local okS, style = pcall(require, "ge/extensions/raceprep/classStyle")
    if okS and style.drawBadge then style.drawBadge(entry) else Text(entry and (entry.class .. " " .. entry.pi) or "--") end
end

local function slotList(vehID)
    local d = core_vehicle_manager and core_vehicle_manager.getVehicleData(vehID)
    local snapshot=rawget(_G,"raceprepRatings") and ((raceprepRatings.getLiveCarData and raceprepRatings.getLiveCarData(vehID)) or (raceprepRatings.getCarData and raceprepRatings.getCarData(vehID)))
    -- labels computed before the engine data arrived say "reading dyno...": refresh them
    local stale = cache.pending and os.clock() - (cache.at or 0) > 1
    if stale or cache.vehID ~= vehID or cache.vdata ~= (d and d.vdata) or cache.snapshot~=snapshot then
        cache.snapshot=snapshot
        cache.vehID, cache.vdata = vehID, d and d.vdata
        local ok, list = pcall(upgrades.list, vehID)
        cache.list = ok and list or {}
        cache.at, cache.pending = os.clock(), false
        for _, e in ipairs(cache.list) do
            for _, o in ipairs(e.options or {}) do
                if tostring(o.title):find("reading dyno", 1, true) then cache.pending = true end
            end
        end
        if not ok then message = "Could not read the car's parts: " .. tostring(list) end
    end
    return cache.list
end

-- one line of help at the top of each tab
local TAB_HELP = {
    engine = "Pick a Stage package to fit several parts at once, or choose parts one by one below. The graph compares stock with your engine.",
    drivetrain = "A race transmission or race differential unlocks its settings in the Tuning tab and adds tuning-potential PI.",
    suspension = "Race coilovers unlock springs, dampers, ride height and anti-roll bars in the Tuning tab.",
    tyres = "Grip: Stock < Sport < Semi-slick < Race slick. Wider tyres grip more. Front and rear can differ.",
    aero = "More downforce = more grip in fast corners, but more drag. On a low-power car a big kit can make it slower overall (check the PI change after fitting). Kits are rated at their maximum; set front/rear in the Tuning tab.",
    nitrous = "Nitrous gives a boost while the button is held. Some races ban it.",
}
local HUB = "camso_tuning_parameters_engine"

local function drawParts(group, list, vehID, allowed, reason, entry)
    local c = BJI.Utils.Style.TEXT_COLORS
    if not allowed then
        Text(reason or "Not allowed here.", { color = c.ERROR, wrap = true })
    end
    local any = false
    local leftWidth=(group.key=="engine" or group.key=="aero") and .18 or .42
    if BeginTable("raceprep-upgrades-" .. group.key, {
            { label = "##up-l", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = leftWidth },
            { label = "##up-v", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 1-leftWidth },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        for i, e in ipairs(list) do
            -- the engine-parts hub is fitted with a button (drawEngineHub), not shown as a part
            if e.group == group.key and e.slot ~= HUB then
                any = true
                TableNewRow()
                Text(tostring(e.title))
                TableNextColumn()
                local options = {}
                local unsafe = {}
                for _, o in ipairs(e.options) do
                    table.insert(options, { value = o.name, label = o.unsafe and (o.title .. " - " .. o.unsafe) or o.title })
                    unsafe[o.name] = o.unsafe
                end
                local picked = Combo("raceprep-up-" .. group.key .. i, e.current, options, { width = -1, disabled = not allowed })
                if TooltipText then
                    local tips={}
                    for _,option in ipairs(e.options) do if option.tooltip then tips[#tips+1]=option.title.."\n"..option.tooltip end end
                    if #tips>0 then TooltipText(table.concat(tips,"\n\n")) end
                end
                if picked and picked ~= e.current and unsafe[picked] then
                    message = "Not fitted: " .. tostring(unsafe[picked]) .. "."
                elseif picked and picked ~= e.current and allowed then
                    local okFit, why = upgrades.apply(vehID, e, picked, entry)
                    if okFit then
                        message = "Fitting " .. tostring(upgrades.lastChange and upgrades.lastChange.label or picked) .. "..."
                        cache.vehID = nil
                    elseif why then
                        message = "Not fitted: " .. tostring(why) .. "."
                    end
                end
            end
        end
        EndTable()
    end
    if not any then
        Text("This car has no other " .. string.lower(group.label) .. " parts.", { color = c.DISABLED, wrap = true })
    end
end

-- KTS (Kagoni Tyre Simulation) presets, for the compound tooltip
local SLICK_NOTES={
    supersoft='Most grip (Soft + 2 %). Wears 2x as fast; works from 85 C, overheats past 105 C. Qualifying tyre.',
    soft='Automation Soft Race grip. Wears 1.55x as fast; works from 95 C, overheats past 115 C.',
    medium='Automation Medium Race grip (about 10 % less than Soft). Normal wear; works from 105 C to 130 C.',
    hard='Automation Hard Race grip (about 23 % less than Soft). Wears 0.8x as fast; needs 115 C, holds to 140 C.',
}
local function drawTyres(list,vehID,allowed,reason,before,rules,onGrid)
    local c=BJI.Utils.Style.TEXT_COLORS
    if not allowed then Text(reason,{color=c.DISABLED,wrap=true}) end
    local veh=currentVehicle()
    local model=veh and veh:getJBeamFilename()
    if not (upgrades.catalog.stocks and upgrades.catalog.stocks[tostring(model)..'/front']) then
        drawParts({key='tyres'},list,vehID,allowed,reason,before)
        return
    end
    local entries,stocks,current={},{},{}
    for _,axle in ipairs({'front','rear'}) do
        stocks[axle]=upgrades.catalog.stocks[tostring(model)..'/'..axle]
        for _,slot in ipairs(list) do
            if slot.slot=='Camso_wheels_'..axle then entries[axle]=slot;break end
        end
        local info=entries[axle] and upgrades.catalog.parts[entries[axle].current]
        current[axle]={compound=info and info.compound or 'stock',offset=info and info.offsetMM or 0}
    end
    local function partFor(axle,compound,offset)
        local stock=stocks[axle]
        if compound=='stock' and offset==0 then return stock.part end
        for name,part in pairs(upgrades.catalog.parts) do
            if part.kind=='tyre' and part.model==model and part.stockPart==stock.part and part.compound==compound and part.offsetMM==offset then return name end
        end
    end
    local function effective(axle,compound) return compound=='stock' and stocks[axle].compound or compound end
    for _,axle in ipairs({'front','rear'}) do
        local stock,entry=stocks[axle],entries[axle]
        if stock and entry then
            local compound,offset=current[axle].compound,current[axle].offset
            Text(axle=='front' and 'Front tyres' or 'Rear tyres',{color=c.HIGHLIGHT})
            local stockName=upgrades.COMPOUND_LABELS[stock.compound] or stock.compound:gsub('_',' ')
            local compoundOptions={}
            for _,value in ipairs(upgrades.COMPOUNDS) do
                local label=value=='stock' and ('Stock ('..stockName..')') or upgrades.COMPOUND_LABELS[value]
                local slick=upgrades.slickOf(effective(axle,value))
                if onGrid and slick and not upgrades.slickAllowed(rules,slick) then label=label..' - not allowed in this race' end
                compoundOptions[#compoundOptions+1]={value=value,label=string.format('%s / %g mm',label,stock.widthMM+offset)}
            end
            local picked=Combo('rp-tyre-compound-'..axle,compound,compoundOptions,{disabled=not allowed,width=300})
            local slickNow=upgrades.slickOf(effective(axle,compound))
            if slickNow and TooltipText then TooltipText(upgrades.SLICK_LABELS[slickNow]..': '..SLICK_NOTES[slickNow]) end
            SameLine()
            local widths={-20,0,20,40}
            local widthOptions={}
            for _,delta in ipairs(widths) do widthOptions[#widthOptions+1]={value=delta,label=string.format('%g mm (%s)',stock.widthMM+delta,delta==0 and 'stock' or string.format('%+d mm',delta))} end
            local width=Combo('rp-tyre-width-'..axle,offset,widthOptions,{disabled=not allowed,width=180})
            if picked or width then
                local targetCompound,targetOffset=picked or compound,width or offset
                local slick=upgrades.slickOf(effective(axle,targetCompound))
                if onGrid and slick and not upgrades.slickAllowed(rules,slick) then
                    message='Not fitted: Race slick '..upgrades.SLICK_LABELS[slick]..' is not allowed in this race.'
                else
                    local changes={}
                    local target=partFor(axle,targetCompound,targetOffset)
                    if target and target~=entry.current then changes[#changes+1]={entry,target} end
                    -- one slick compound per car (tyre simulation): the other axle follows
                    local other=axle=='front' and 'rear' or 'front'
                    local otherSlick=entries[other] and upgrades.slickOf(effective(other,current[other].compound))
                    if picked and slick and otherSlick and otherSlick~=slick then
                        local otherCompound=effective(other,'stock')==targetCompound and 'stock' or targetCompound
                        local otherTarget=partFor(other,otherCompound,current[other].offset)
                        if otherTarget and otherTarget~=entries[other].current then changes[#changes+1]={entries[other],otherTarget} end
                    end
                    if #changes>0 then
                        local label=(axle=='front' and 'Front' or 'Rear')..' tyres: '..(upgrades.COMPOUND_LABELS[targetCompound] or targetCompound)..
                            string.format(' %g mm',stock.widthMM+targetOffset)..(#changes>1 and ' (both axles)' or '')
                        if upgrades.applyMany(vehID,changes,label,before) then
                            message='Fitting '..label..'...';cache.vehID=nil
                        end
                        return
                    end
                end
            end
            Separator()
        end
    end
    Text('Grip from Automation\'s own compounds; rims stay the same. Race slick compounds also set the tyre simulation\'s wear and temperature window, one compound per car: changing it on one axle changes both when both run slicks.',
        {color=c.DISABLED,wrap=true})
end

local function drawTuning(vehID, freeroam)
    local c = BJI.Utils.Style.TEXT_COLORS
    if not freeroam then
        Text("On the race grid, tune in the Race Prep window's Setup tab (it follows the race rules).",
            { color = c.DISABLED, wrap = true })
        return
    end
    local d = core_vehicle_manager and core_vehicle_manager.getVehicleData(vehID)
    if not d or not d.vdata then return end
    if varsFor ~= vehID then varsFor, pendingVars = vehID, {} end
    local vars = d.vdata.variables or {}
    local current = d.config.vars or {}
    local owners=tuningPolicy.owners(d.vdata)
    local groups, names = {}, {}
    -- not car tuning: camera, force feedback, export placement offsets
    local HIDDEN = { ["Camera Positions"] = true, ["Force Feedback"] = true, ["Vehicle Advanced Settings"] = true }
    for name, meta in pairs(vars) do
        if type(meta) == "table" and meta.type == "range" and meta.hideInUI ~= true and not HIDDEN[tostring(meta.category)] and
            tonumber(meta.min) and tonumber(meta.max) and tonumber(meta.max) > tonumber(meta.min) then
            local cat = tostring(meta.category or "Other")
            if not groups[cat] then groups[cat] = {}; table.insert(names, cat) end
            table.insert(groups[cat], { name = name, meta = meta })
        end
    end
    table.sort(names)
    if #names == 0 then
        Text("This car has no tuning settings.", { color = c.DISABLED })
        return
    end
    Text("Settings unlock when the matching race part is fitted (gear ratios need a race transmission, springs need race coilovers...). Tyre pressure, brakes and fuel are always adjustable. Race parts are rated at their best setting, so tuning never changes PI.",
        { color = c.DISABLED, wrap = true })
    for _, cat in ipairs(names) do
        local open, total = 0, #groups[cat]
        for _, v in ipairs(groups[cat]) do
            if tuningPolicy.allowed(d.vdata, v.name, v.meta, owners) then open = open + 1 end
        end
        local count = open == total and "all adjustable" or open == 0 and "locked" or string.format("%d of %d adjustable", open, total)
        if BeginTree(string.format("%s  (%s)##raceprep-up-tune-%s", cat, count, cat)) then
            table.sort(groups[cat], function(a, b) return tostring(a.meta.title or a.name) < tostring(b.meta.title or b.name) end)
            for _, v in ipairs(groups[cat]) do
                local m = v.meta
                local unlocked,lockReason=tuningPolicy.allowed(d.vdata,v.name,m,owners)
                local value = pendingVars[v.name] or tonumber(current[v.name]) or tonumber(m.val) or tonumber(m.default) or tonumber(m.min)
                Text(tostring(m.title or v.name),{color=unlocked and c.DEFAULT or c.DISABLED})
                if not unlocked then
                    pendingVars[v.name]=nil
                    if lockReason then SameLine(); Text("("..tostring(lockReason):lower()..")",{color=c.DISABLED}) end
                end
                if TooltipText then
                    local tip=tostring(m.description or "")..(lockReason and ('\n'..lockReason) or '')
                    if v.name=="$rpAeroFront" or v.name=="$rpAeroRear" then tip=tip..string.format("\n%.1f kg at 200 km/h (requested).",value/2.20462262185) end
                    TooltipText(tip)
                end
                SameLine()
                local unit = tostring(m.unit or ""):gsub("%%", "%%%%")
                local step = tonumber(m.stepDis) or tonumber(m.step)
                -- Automation's balancing multiplier can reach 0 (no inertia: the engine cannot turn)
                local minimum = tonumber(m.min)
                if v.name == "$EngineInertiaMod" then minimum = math.max(minimum, 0.25) end
                local new = SliderFloat("raceprep-up-var" .. v.name, math.max(value, minimum), minimum, tonumber(m.max),
                    { disabled=not unlocked,precision = (step and step >= 1) and 0 or 2, formatRender = "%." .. ((step and step >= 1) and 0 or 2) .. "f " .. unit })
                if new then pendingVars[v.name] = new end
            end
            EndTree()
        end
    end
    if next(pendingVars) then
        if Button("raceprep-up-apply-vars", "Apply tuning", { btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS }) then
            local pm = extensions.core_vehicle_partmgmt
            if pm and pm.setConfigVars then pm.setConfigVars(pendingVars, true) end
            pendingVars = {}
            message = "Tuning applied."
        end
        SameLine()
        if Button("raceprep-up-reset-vars", "Discard", { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING }) then
            pendingVars = {}
        end
    end
end

local function body()
    local c = BJI.Utils.Style.TEXT_COLORS
    local veh = currentVehicle()
    if not veh then
        Text("Get in your own car to upgrade it.", { color = c.DISABLED })
        return
    end
    local vehID = veh:getID()
    local freeroam, onGrid, rules = context()
    local entry, status = ratingOf(vehID)
    local d = core_vehicle_manager and core_vehicle_manager.getVehicleData(vehID)
    -- the car's own name and config (every export's part info just says
    -- "Automation Exported Car")
    local model = veh:getJBeamFilename()
    local carName = model
    pcall(function()
        local m = core_vehicles.getModel(model)
        local info = m and m.model or {}
        carName = ((info.Brand and info.Brand ~= "") and (info.Brand .. " ") or "") .. tostring(info.Name or model)
        local key = d and d.config and d.config.partConfigFilename and d.config.partConfigFilename:match("([^/]+)%.pc$")
        local cfg = key and core_vehicles.getConfig(model, key)
        -- the vehicle list decorates config names with "[C 478]" badges; the badge is drawn separately here
        local cfgName = cfg and cfg.Configuration and tostring(cfg.Configuration):gsub("%s*%[[EDCBASRPX] %d+%]%s*$", "")
        if cfgName and cfgName ~= "" then carName = carName .. " - " .. cfgName end
    end)
    Text(carName, { color = c.HIGHLIGHT })
    SameLine()
    badge(entry)
    if entry and entry.tuningPotentialPI then
        SameLine()
        Text(string.format('+%d PI tuning potential',entry.tuningPotentialPI),{color=c.DISABLED})
    end
    local summary=upgrades.summary(vehID)
    if summary then
        Text(string.format('%.0f hp | %.0f lbs | %.1f%% front / %.1f%% rear',summary.hp,summary.massLB,summary.frontShare*100,summary.rearShare*100))
        if TooltipText then TooltipText(string.format('%.1f kW | %.1f kg%s. Power is the engine as it is now; PI rates race parts at their best setting.',summary.kw,summary.massKG,summary.reference and " (40 kg fuel reference; live reading pending)" or " (live mass, including fuel)")) end
    else Text('Reading car power and weight...', {color=c.DISABLED}) end
    local last = upgrades.lastChange
    if last and last.vehID == vehID then
        Text(tostring(last.label), { color = c.DISABLED })
        if last.before and entry and last.before.pi ~= entry.pi then
            SameLine()
            Text(string.format("   %s %d -> %s %d (%+d PI)", last.before.class, last.before.pi, entry.class, entry.pi,
                entry.pi - last.before.pi), { color = entry.pi > last.before.pi and c.HIGHLIGHT or c.SUCCESS })
        elseif not entry then
            SameLine()
            Text("   new rating pending...", { color = c.DISABLED })
        end
    end
    if #upgrades.history > 0 and upgrades.history[#upgrades.history].vehID == vehID then
        if Button("raceprep-up-undo", "Undo last change", { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING }) then
            upgrades.undo(vehID)
            cache.vehID = nil
        end
    end
    if message then
        local refused = message:find("^Not fitted") or message:find("^Could not")
        Text(message, { color = refused and c.ERROR or c.DISABLED, wrap = true })
    end
    if onGrid then
        Text("Race grid: class / PI limits are checked when you press Ready.", { color = c.DISABLED, wrap = true })
    end
    Separator()

    local list = slotList(vehID)
    if BeginTabBar("raceprep-upgrades-tabs") then
        for _, g in ipairs(upgrades.GROUPS) do
            if BeginTabItem(g.label .. "##raceprep-up-tab-" .. g.key) then
                local allowed, reason = upgrades.allowed(g.key, rules, freeroam, onGrid)
                if TAB_HELP[g.key] then Text(TAB_HELP[g.key], { color = c.DISABLED, wrap = true }) end
                if g.key=='engine' then
                    -- extra engine parts hang off a hub part: offer it as one clear button
                    for _, e in ipairs(list) do
                        if e.slot == HUB and (e.current or "") == "" then
                            local hub
                            for _, o in ipairs(e.options) do if o.name ~= "" then hub = o.name end end
                            if hub and Button("rp-engine-hub", "Show more engine parts (exhaust, camshaft, displacement, turbo / supercharger, coolers)",
                                    { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO, disabled = not allowed }) then
                                if upgrades.apply(vehID, e, hub, entry) then message = "Adding engine part slots..."; cache.vehID = nil end
                            end
                        end
                    end
                end
                if g.key=='engine' and upgrades.engineInfo(veh:getJBeamFilename()) then
                    for number=0,3 do
                        if number>0 then SameLine() end
                        local fitted=upgrades.packageFitted(vehID,number)
                        if Button('rp-engine-package-'..number,upgrades.packageEffect(vehID,number)..(fitted and '  (fitted)' or ''),
                                {disabled=not allowed or fitted,btnStyle=fitted and BJI.Utils.Style.BTN_PRESETS.SUCCESS or nil}) then
                            local ok,msg=upgrades.applyPackage(vehID,number,entry)
                            message=ok and (number==0 and 'Removing engine upgrade parts...' or ('Fitting Stage '..number..' engine parts...')) or msg
                            cache.vehID=nil
                        end
                    end
                    engineGraph.draw(upgrades.engineCurves(vehID))
                end
                if g.key=='tyres' then drawTyres(list,vehID,allowed,reason,entry,rules,onGrid)
                else drawParts(g, list, vehID, allowed, reason, entry) end
                EndTabItem()
            end
        end
        if BeginTabItem("Tuning##raceprep-up-tab-tuning") then
            drawTuning(vehID, freeroam)
            EndTabItem()
        end
        EndTabBar()
    end

    Separator()
    Text("Save this car (parts + tuning) as its own config:")
    local typed = InputText and InputText("raceprep-up-save-name", saveName, { width = 260 })
    if typed then saveName = typed end
    SameLine()
    if Button("raceprep-up-save", "Save setup", { btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS }) then
        local name = saveName ~= "" and saveName or
            string.format("%s (%s)", tostring(d and d.vdata and d.vdata.information and d.vdata.information.name or "Car"),
                entry and (entry.class .. " " .. entry.pi) or "custom")
        local _, msg = upgrades.save(name)
        saveMessage = msg
    end
    if saveMessage then Text(saveMessage, { color = c.DISABLED, wrap = true }) end
    Text("Parts come from each car's own export; ratings for new part combinations are estimates.",
        { color = c.DISABLED, wrap = true })
end

W.getState = function()
    return W.show == true
end

W.onClose = function()
    W.show = false
end

W.body = body

return W
