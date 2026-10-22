-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
---@class BJIWindowRacePrep : BJIWindow
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local W = {
    name = "RacePrep",
    minSize = ImVec2(560, 520),
    maxSize = ImVec2(900, 860),
    flags = {
        BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE,
    },
}

local TITLE = "Race Preparation"

local pendingVars = {}
local variableVehicleID
-- identity + size of the car's variable list when the cache was built
local variableSignature
local variableGroups = {}
local hasVariableChanges = false
-- Automation exports set the centre (transfer case) split from this variable,
-- and their active AWD controller reads it when the car loads; the Diff tab
-- edits it instead of the runtime split, and Setup hides it
local SPLIT_VAR = "$torquesplit"
local splitVariable
-- aero values (downforce, drag, frontal area) live in their own tab and rule
local aeroVariables = {}
-- brake cooling ducts (added by Kagoni Tyre Simulation) get their own tab
local coolingVariables = {}
local lastApplyMessage
-- fuel levels the driver chose, in percent per tank; re-applied after a setup
-- reload (the respawn refills the tanks) and right before marking ready
local fuelTargets = {}

-- differential settings being edited (deviceName -> settings) for one vehicle
local diffDraft = {}
local diffDraftVehicle
local diffDirty = false
local diffMessage
local lastDiffRequest = 0
local lastRuleCheck = 0

-- rules being edited in the Rules tab
local rulesScope = "race"
local rulesEditorOpen = false
local rulesDraft
local rulesDraftKey

-- defined with the Diff tab below; used by the Race tab's Ready button
-- per-frame memo: the Ready button and tabs ask for the same rules and checks
-- several times a frame; compute them once (frameStamp = ctxt.now)
local frameStamp
local frameMemo = {}
local VARIABLE_CHECK_MS = 250
local lastVariableCheck = -1e9

local sanitizeDiff
local splitViolation
local aeroViolation
local rating = require("ge/extensions/raceprep/rating")
local classStyle = require("ge/extensions/raceprep/classStyle")
local partsViolation
local drawPartsAndAids
local drawRulesSummary
local drawSessionRules

-- BeamJoy windows each define this locally; it is not a global
local function getDiffTime(time, now)
    if not time then
        return 0
    end
    return math.ceil((time - now) / 1000)
end

local function getScale()
    return BJI_LocalStorage.get(BJI_LocalStorage.GLOBAL_VALUES.UI_SCALE) or 1
end

local function getRace()
    if not BJI_Scenario or not BJI_Scenario.TYPES or not BJI_Scenario.TYPES.RACE_MULTI then
        return nil
    end
    local race = BJI_Scenario.get(BJI_Scenario.TYPES.RACE_MULTI)
    if race and race.state == race.STATES.GRID and race.grid and race.grid.timeout then
        return race
    end
end

local function concealStockGridWindow()
    -- RaceMulti is a subview of the registered Race window. BeamJoy does not
    -- publish a BJI_Win_RaceMulti global, so wrap the owning window instead.
    local raceWindow = rawget(_G, "BJI_Win_Race")
    if raceWindow and not raceWindow._racePrepWrapped then
        local originalGetState = raceWindow.getState
        raceWindow.getState = function()
            if getRace() then
                return false
            end
            return originalGetState and originalGetState() or false
        end
        raceWindow._racePrepWrapped = true
    end
end

local function setWindowTitle()
    -- BeamJoy titles windows from its language table (windows.<name>);
    -- languages reload, so this is checked every time the state is polled
    local messages = BJI_Lang and BJI_Lang.Messages
    if type(messages) == "table" and type(messages.windows) == "table" and
        messages.windows[W.name] == nil then
        messages.windows[W.name] = TITLE
    end
end

local function isRaceParticipant(race)
    return race and race.isParticipant and race.isParticipant() or false
end

local function isConfigForced(race)
    return race and race.settings and race.settings.config ~= nil
end

local function canEditSetup(race)
    return race and isRaceParticipant(race) and not race.isReady() and
        BJI_Veh.isCurrentVehicleOwn() and BJI_Scenario.canReplaceVehicle()
end

local function canEditFuel(race)
    return race and isRaceParticipant(race) and not race.isReady() and
        BJI_Veh.isCurrentVehicleOwn()
end

local function runtime()
    return rawget(_G, "bjiRacePrep")
end

local function getRules(race)
    local rt = runtime()
    local key = "rules:" .. tostring(race and race.raceID)
    if frameStamp and frameMemo[key] then
        return frameMemo[key]
    end
    if rt then
        local rules = rt.getRules(race and race.raceID)
        if frameStamp then
            frameMemo[key] = rules
        end
        return rules
    end
    return {
        tuning = true, fuel = true, aero = true, diff = true,
        diffModes = { open = true, lsd = true, locked = true },
        centreSplit = true, centreSplitMin = 0.2, centreSplitMax = 0.8,
        maxPreload = 500, maxLock = 100, trackTempFixed = false, trackTemp = 30, tyreWear = "driver",
        parts = { engine = "any", drivetrain = "any", suspension = "any", tyres = "any", body = "any" },
        nitrous = true, abs = "driver", tc = "driver", esc = "driver",
        startType = "standing", paceSpeed = 80,
        slickCompounds = { supersoft = true, soft = true, medium = true, hard = true },
    }
end

local function ratingViolation(race)
    if frameStamp and frameMemo.rating ~= nil then return frameMemo.rating or nil end
    local rt = rawget(_G, "raceprepRatings")
    local veh = BJI_Veh.getCurrentVehicleOwn()
    local entry, status
    if rt and veh then entry, status = rt.getVehicle(veh:getID()) end
    local rules = getRules(race)
    local reason = rating.violation(rules, entry, status)
    if not reason and veh then
        -- allowed race slick compounds (1.8.5)
        local ok, upgrades = pcall(require, "ge/extensions/raceprep/upgrades")
        if ok and upgrades.compoundViolation then reason = upgrades.compoundViolation(veh:getID(), rules) end
    end
    if frameStamp then frameMemo.rating = reason or false end
    return reason
end
local function ratingTooltip(entry)
    if not entry then return end
    TooltipText(string.format("General %s %d | Speed %s %d | Technical %s %d\n%s\nSport mode, 40 kg fuel, warm KTS tyres%s",
        entry.class, entry.pi, rating.classOf(entry.pi_speed), entry.pi_speed,
        rating.classOf(entry.pi_technical), entry.pi_technical, entry.source or "computed",
        entry.flag and ("\n" .. entry.flag) or ""))
end

local function translateTuningText(value, prefix)
    if type(value) == "table" and value.txt and value.ctx and core_locales then
        return core_locales.contextTranslate(value.txt, value.ctx)
    elseif type(value) == "string" and core_locales and core_locales.translateWithPrefixFallback then
        return core_locales.translateWithPrefixFallback(value, prefix)
    end
    return tostring(value or "")
end

local function getVehicleTuningData()
    local vehicle = BJI_Veh.getCurrentVehicleOwn()
    if not vehicle then
        return nil
    end
    local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehicle:getID())
    if not vehicleData or not vehicleData.vdata or not vehicleData.config then
        return nil
    end
    return vehicle:getID(), vehicleData
end

---@param keepPending boolean? keep unapplied edits (same car, list re-read)
local function buildVariableGroups(keepPending)
    variableGroups = {}
    local vehicleID, vehicleData = getVehicleTuningData()
    if not keepPending or vehicleID ~= variableVehicleID then
        pendingVars = {}
        hasVariableChanges = false
    end
    variableVehicleID = vehicleID
    splitVariable = nil
    aeroVariables = {}
    coolingVariables = {}
    if not vehicleData then
        return
    end

    local vars = vehicleData.vdata.variables or {}
    local current = vehicleData.config.vars or {}
    for name, meta in pairs(vars) do
        if type(meta) == "table" and meta.type == "range" and meta.hideInUI ~= true then
            local minimum, maximum = tonumber(meta.min), tonumber(meta.max)
            local value = tonumber(current[name]) or tonumber(meta.val) or tonumber(meta.default)
            if name == SPLIT_VAR and minimum and maximum and maximum > minimum and value then
                splitVariable = {
                    min = minimum,
                    max = maximum,
                    default = tonumber(meta.default),
                    value = math.clamp(value, minimum, maximum),
                }
            elseif minimum and maximum and maximum > minimum and value then
                local category = translateTuningText(meta.category or "Other",
                    "ui.vehicleconfig.variables.category.")
                local raw = string.lower(table.concat({ tostring(meta.category or ""), tostring(meta.subCategory or ""),
                    tostring(name), type(meta.title) == "string" and meta.title or "" }, " "))
                local isAero = raw:find("aero", 1, true) or raw:find("downforce", 1, true) or
                    name == "$bodyDragCoef" or name == "$frontalAreaAdjust"
                -- Automation files brake power under Suspension / Brakes; show it with
                -- the other brake values (brake offset is geometry and stays put)
                if not isAero and string.lower(tostring(meta.subCategory or "")) == "brakes" then
                    category = translateTuningText("Brakes", "ui.vehicleconfig.variables.category.")
                end
                local isCooling = tostring(name):find("CoolingDuct", 1, true) ~= nil
                local targetList
                if isCooling then
                    targetList = coolingVariables
                elseif isAero then
                    targetList = aeroVariables
                else
                    variableGroups[category] = variableGroups[category] or {}
                    targetList = variableGroups[category]
                end
                table.insert(targetList, {
                    name = name,
                    title = translateTuningText(meta.title or name,
                        "ui.vehicleconfig.variables.title."),
                    description = translateTuningText(meta.description or "",
                        "ui.vehicleconfig.variables.description."),
                    subCategory = translateTuningText(meta.subCategory or "",
                        "ui.vehicleconfig.variables.subCategory."),
                    unit = tostring(meta.unit or ""),
                    min = minimum,
                    max = maximum,
                    default = tonumber(meta.default),
                    value = math.clamp(value, minimum, maximum),
                    -- display range, as BeamNG's own tuning screen shows it
                    minDis = tonumber(meta.minDis),
                    maxDis = tonumber(meta.maxDis),
                    stepDis = tonumber(meta.stepDis),
                })
            end
        end
    end

    local function byTitle(a, b)
        if a.subCategory == b.subCategory then
            return a.title:lower() < b.title:lower()
        end
        return a.subCategory:lower() < b.subCategory:lower()
    end
    table.sort(aeroVariables, byTitle)
    table.sort(coolingVariables, byTitle)
    for _, variables in pairs(variableGroups) do
        table.sort(variables, function(a, b)
            if a.subCategory == b.subCategory then
                return a.title:lower() < b.title:lower()
            end
            return a.subCategory:lower() < b.subCategory:lower()
        end)
    end
end

-- Re-read the list when the car changes, when a reload gives it a new list,
-- or when a mod adds values later: Kagoni Tyre Simulation injects its brake
-- cooling sliders in onVehicleSpawned, after the car's own variables exist.
local function updateVariableCache()
    local now = frameStamp or 0
    if variableSignature and now - lastVariableCheck < VARIABLE_CHECK_MS then
        return
    end
    lastVariableCheck = now
    local vehicle = BJI_Veh.getCurrentVehicleOwn()
    local vehicleID = vehicle and vehicle:getID() or nil
    local signature = "none"
    if vehicleID then
        local data = extensions.core_vehicle_manager.getVehicleData(vehicleID)
        local vars = data and data.vdata and data.vdata.variables
        local count = 0
        for _ in pairs(vars or {}) do
            count = count + 1
        end
        signature = string.format("%d:%s:%d", vehicleID, tostring(vars), count)
    end
    if signature ~= variableSignature then
        variableSignature = signature
        buildVariableGroups(vehicleID ~= nil and vehicleID == variableVehicleID)
    end
end

local function getFuelTanks()
    local gameVehicleID = BJI_Context.User.currentVehicle
    local serverVehicleID = gameVehicleID and BJI_Veh.getVehIDByGameVehID(gameVehicleID)
    local vehicleData = serverVehicleID and BJI_Context.User.vehicles[serverVehicleID]
    return vehicleData and vehicleData.tanks or {}
end

local function applyFuelTargets()
    local tanks = getFuelTanks()
    for tankName, percent in pairs(fuelTargets) do
        local tank = tanks[tankName]
        if tank and tank.maxEnergy and tank.maxEnergy > 0 then
            BJI_Veh.setFuel(tankName, tank.maxEnergy * percent / 100)
        end
    end
end

--- applies pendingVars with a car reload; returns the message to show
local function applySetupVars(race)
    if canEditSetup(race) and extensions.core_vehicle_partmgmt and
        extensions.core_vehicle_partmgmt.setConfigVars then
        extensions.core_vehicle_partmgmt.setConfigVars(pendingVars, true)
        pendingVars = {}
        hasVariableChanges = false
        variableVehicleID = nil
        variableSignature = nil
        if next(fuelTargets) then
            BJI_Async.delayTask(applyFuelTargets, 2000, "BJIRacePrepRestoreFuel")
        end
        return "Setup applied. The car reloaded on its grid slot."
    end
    return "Setup could not be applied in the current race state."
end

local function drawCountdown(race, ctxt)
    local seconds = math.max(0, getDiffTime(race.grid.timeout, ctxt.now))
    local total = BJI_Context.BJC and BJI_Context.BJC.Race and
        tonumber(BJI_Context.BJC.Race.GridTimeout) or nil
    if not total or total < seconds then
        total = math.max(seconds, 1)
    end

    local participants = race.grid.participants or {}
    local readyCount = 0
    for _, playerID in ipairs(participants) do
        if table.includes(race.grid.ready or {}, playerID) then
            readyCount = readyCount + 1
        end
    end

    Text(race.raceName or "Race", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
    if race.settings and race.settings.laps then
        SameLine()
        Text(race.settings.laps == 1 and "(1 lap)" or string.var("({1} laps)", { race.settings.laps }),
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
    end

    local barColor = seconds <= 10 and BJI.Utils.Style.TEXT_COLORS.ERROR or
        seconds <= 30 and BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT or
        BJI.Utils.Style.TEXT_COLORS.SUCCESS
    ProgressBar(math.clamp(seconds / total, 0, 1), {
        text = string.var("Grid closes in {1}   |   {2}/{3} drivers ready", {
            BJI.Utils.UI.PrettyDelay(seconds), readyCount, #participants,
        }),
        color = barColor,
        height = 26,
    })
    local rt = runtime()
    local temps = rt and rt.trackTemp
    if temps then
        Text(string.format("Air %.0f\194\176C   Track %.0f\194\176C%s%s", temps.air, temps.track,
            temps.fixed and "  (set by race rules)" or "", temps.wet and "  wet" or ""),
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
        TooltipText("Track temperature follows air temperature, sun and cloud cover, and feeds the tyre temperatures (Kagoni Tyre Simulation).")
    end
    Separator()
end

local function drawRaceTab(race, ctxt)
    local participant = isRaceParticipant(race)
    local ready = race.isReady()
    local ownsVehicle = BJI_Veh.isCurrentVehicleOwn()
    local canJoinLeave = not ready and BJI_Perm.canSpawnVehicle() and BJI_Tournament.canJoinActivity()
    local places = math.max(#(race.grid.startPositions or {}) - #(race.grid.participants or {}), 0)

    if not participant then
        Text("Join the grid to choose a car and prepare your setup.", { wrap = true })
        if Button("raceprep-join", "Join race", {
                btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS,
                disabled = not canJoinLeave or places == 0,
                width = 200,
            }) then
            BJI_Tx_scenario.RaceMultiUpdate(race.CLIENT_EVENTS.JOIN)
        end
        SameLine()
        Text(places == 1 and "1 grid slot left" or string.var("{1} grid slots left", { places }),
            { color = places == 0 and BJI.Utils.Style.TEXT_COLORS.ERROR or BJI.Utils.Style.TEXT_COLORS.DISABLED })
    else
        local currentModel = ownsVehicle and BJI_Veh.getCurrentModel() or nil
        local modelName = currentModel and (BJI_Veh.getModelLabel(currentModel) or currentModel) or nil
        Text("Your car:")
        SameLine()
        Text(modelName or "none selected", {
            color = modelName and BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT or BJI.Utils.Style.TEXT_COLORS.ERROR,
        })
        local ratings = rawget(_G, "raceprepRatings")
        local ownCar = ownsVehicle and BJI_Veh.getCurrentVehicleOwn()
        local entry = ratings and ownCar and ratings.getVehicle(ownCar:getID())
        if ownsVehicle then
            SameLine()
            if entry then
                classStyle.drawBadge(entry, BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT)
            else
                Text("Rating pending", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
            end
            ratingTooltip(entry)
        end

        if not ready then
            local forced = isConfigForced(race)
            if Button("raceprep-select-car", forced and "Choose paint" or
                    (ownsVehicle and "Change car" or "Choose a car"), {
                    btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO,
                    disabled = not BJI_Perm.canSpawnVehicle(),
                    width = 200,
                }) then
                BJI_Win_VehSelector.open(true)
            end
            SameLine()
            if Button("raceprep-leave", "Leave grid", {
                    btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING,
                    width = 140,
                }) then
                BJI_Tx_scenario.RaceMultiUpdate(race.CLIENT_EVENTS.JOIN)
            end

            if not ownsVehicle then
                Text("1. Choose a car   2. Set fuel and tuning in Setup   3. Mark ready", {
                    color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true,
                })
            elseif forced then
                Text("This race uses a fixed car configuration. You can still set fuel in Setup.", {
                    color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true,
                })
            else
                Text("Set fuel and tuning in the Setup tab, then mark ready. Ready locks your car.", {
                    color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true,
                })
            end

            local cooldown = math.max(0, getDiffTime(race.grid.readyTime, ctxt.now))
            local readyLabel = "READY"
            if not ownsVehicle then
                readyLabel = "READY  (choose a car first)"
            elseif hasVariableChanges then
                readyLabel = "READY  (unapplied setup changes)"
            elseif diffDirty then
                readyLabel = "READY  (unapplied differential changes)"
            elseif splitViolation(race) then
                readyLabel = "READY  (" .. splitViolation(race) .. ")"
            elseif aeroViolation(race) then
                readyLabel = "READY  (" .. aeroViolation(race) .. ": see Aero tab)"
            elseif ratingViolation(race) then
                readyLabel = "READY  (" .. ratingViolation(race) .. ")"
            elseif partsViolation(race) then
                readyLabel = "READY  (" .. partsViolation(race) .. ")"
            elseif cooldown > 0 then
                readyLabel = string.var("READY  (available in {1})", { BJI.Utils.UI.PrettyDelay(cooldown) })
            end
            if Button("raceprep-ready", readyLabel, {
                    btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS,
                    disabled = not ownsVehicle or hasVariableChanges or diffDirty or splitViolation(race) ~= nil or
                        aeroViolation(race) ~= nil or ratingViolation(race) ~= nil or partsViolation(race) ~= nil or
                        cooldown > 0,
                    width = -1,
                }) then
                local rules = getRules(race)
                if rules.fuel then
                    applyFuelTargets()
                end
                -- re-send the diff, checked against the current rules
                local rt = runtime()
                local veh = BJI_Veh.getCurrentVehicleOwn()
                if rt and veh then
                    local vid = veh:getID()
                    local current = rt.diffSettings[vid]
                    if current and next(current) and rt.diffReports[vid] then
                        rt.applyDiff(vid, sanitizeDiff(current, rt.diffReports[vid], rules))
                    end
                end
                BJI_Tx_scenario.RaceMultiUpdate(race.CLIENT_EVENTS.READY)
            end
            if ownsVehicle then
                drawPartsAndAids(race)
            end
        else
            Text("READY - your car and setup are locked. Waiting for the other drivers.", {
                color = BJI.Utils.Style.TEXT_COLORS.SUCCESS,
                wrap = true,
            })
        end
    end

    Separator()
    local participants = race.grid.participants or {}
    if #participants == 0 then
        Text("No drivers on the grid yet.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
    elseif BeginTable("raceprep-drivers", {
            { label = "Pos", flags = { TABLE_COLUMNS_FLAGS.WIDTH_FIXED } },
            { label = "Driver", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH } },
            { label = "Class / PI", flags = { TABLE_COLUMNS_FLAGS.WIDTH_FIXED } },
            { label = "Status", flags = { TABLE_COLUMNS_FLAGS.WIDTH_FIXED } },
        }, {
            showHeader = true,
            flags = { TABLE_FLAGS.SIZING_STRETCH_PROP, TABLE_FLAGS.ALTERNATE_ROW_BG },
        }) then
        local players = ctxt.players or {}
        for index, playerID in ipairs(participants) do
            local player = players[playerID]
            local isReady = table.includes(race.grid.ready or {}, playerID)
            local isSelf = playerID == BJI_Context.User.playerID
            TableNewRow()
            Text(string.var("P{1}", { index }))
            TableNextColumn()
            local rtSkill = runtime()
            local skill = rtSkill and rtSkill.skillText and rtSkill.skillText(playerID)
            Text((player and player.playerName or ("Player " .. tostring(playerID))) ..
                (isSelf and "  (you)" or "") .. (skill and ("  - skill " .. skill) or ""), {
                    color = isSelf and BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT or BJI.Utils.Style.TEXT_COLORS.DEFAULT,
                })
            TableNextColumn()
            local ratings = rawget(_G, "raceprepRatings")
            local entry = ratings and ratings.getPlayer(playerID)
            if entry then
                classStyle.drawBadge(entry)
            else
                Text("Pending", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
            end
            ratingTooltip(entry)
            TableNextColumn()
            Text(isReady and "READY" or "Preparing", {
                color = isReady and BJI.Utils.Style.TEXT_COLORS.SUCCESS or BJI.Utils.Style.TEXT_COLORS.DISABLED,
            })
        end
        EndTable()
    end
    Text("The race starts when every driver on the grid is ready, or when the grid timer runs out.", {
        color = BJI.Utils.Style.TEXT_COLORS.DISABLED,
        wrap = true,
    })
    local rok, results = pcall(require, "ge/extensions/raceprep/results")
    if rok and results and results.last and not results.visible then
        if Button("raceprep-last-results", "Last race results", { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO }) then
            results.visible = true
        end
    end
end

local function drawFuelControls(race)
    Text("Fuel", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
    local tanks = getFuelTanks()
    local tankNames = {}
    for tankName, tank in pairs(tanks) do
        if tank.maxEnergy and tank.maxEnergy > 0 and tank.energyType ~= "air" then
            table.insert(tankNames, tankName)
        end
    end
    if #tankNames == 0 then
        Text(BJI_Veh.isCurrentVehicleOwn() and "This car reports no adjustable fuel or energy tank." or
            "Choose a car to set its fuel.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    table.sort(tankNames)

    local canEdit = canEditFuel(race)
    if BeginTable("raceprep-fuel", {
            { label = "##raceprep-fuel-name", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.4 },
            { label = "##raceprep-fuel-slider", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.6 },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        for _, tankName in ipairs(tankNames) do
            local tank = tanks[tankName]
            local current = tank.currentEnergy or tank.maxEnergy
            local percent = math.clamp(current / tank.maxEnergy * 100, 0, 100)
            TableNewRow()
            Text(string.var("{1} ({2})", { tankName, tank.energyType or "energy" }))
            TableNextColumn()
            local changed = SliderFloat("raceprep-fuel-" .. tostring(tankName), percent, 0, 100, {
                precision = 0,
                formatRender = "%.0f%%",
                disabled = not canEdit,
            })
            if changed then
                fuelTargets[tankName] = changed
                BJI_Veh.setFuel(tankName, tank.maxEnergy * changed / 100)
            end
        end
        EndTable()
    end
end

local function hasDisplayRange(variable)
    return variable.minDis and variable.maxDis and variable.maxDis ~= variable.minDis
end

local function toDisplay(variable, value)
    if not hasDisplayRange(variable) then
        return value
    end
    return variable.minDis + (value - variable.min) * (variable.maxDis - variable.minDis) / (variable.max - variable.min)
end

local function fromDisplay(variable, shown)
    if not hasDisplayRange(variable) then
        return shown
    end
    return variable.min + (shown - variable.minDis) * (variable.max - variable.min) / (variable.maxDis - variable.minDis)
end

local function displayPrecision(variable)
    local step = variable.stepDis
    if hasDisplayRange(variable) and step and step > 0 then
        return step >= 1 and 0 or step >= 0.1 and 1 or 2
    end
    return variable.unit == "" and 2 or 1
end

local function formatValue(variable, value)
    local precision = displayPrecision(variable)
    return string.format("%." .. precision .. "f", toDisplay(variable, value)) ..
        (variable.unit ~= "" and (" " .. variable.unit) or ""), precision
end

--- one label + slider table row for a tuning variable
local function drawVariableRow(variable, canEdit)
    local own=BJI_Veh.getCurrentVehicleOwn()
    local d=own and core_vehicle_manager.getVehicleData(own:getID())
    local unlocked,reason=require('ge/extensions/raceprep/tuningPolicy').allowed(d and d.vdata or {},variable.name,variable)
    canEdit=canEdit and unlocked
    if not unlocked then pendingVars[variable.name]=nil end
    local value = pendingVars[variable.name] or variable.value
    local isPending = pendingVars[variable.name] ~= nil and pendingVars[variable.name] ~= variable.value
    TableNewRow()
    Text((isPending and "* " or "") .. variable.title, {
        color = not unlocked and BJI.Utils.Style.TEXT_COLORS.DISABLED or isPending and BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT or BJI.Utils.Style.TEXT_COLORS.DEFAULT,
    })
    local tooltip = variable.description
    if reason then tooltip=(tooltip or '')..'\n'..reason end
    if variable.name=="$rpAeroFront" or variable.name=="$rpAeroRear" then
        tooltip=tooltip..string.format("\n%.1f kg at 200 km/h (requested); front/rear share the kit cap.",value/2.20462262185)
    end
    if variable.default then
        tooltip = (tooltip ~= "" and (tooltip .. "\n") or "") ..
            "Default: " .. formatValue(variable, variable.default)
    end
    TooltipText(tooltip ~= "" and tooltip or nil)
    TableNextColumn()
    local precision = displayPrecision(variable)
    local lo, hi = toDisplay(variable, variable.min), toDisplay(variable, variable.max)
    local changed = SliderFloat("raceprep-var-" .. variable.name, toDisplay(variable, value),
        math.min(lo, hi), math.max(lo, hi), {
            precision = precision,
            formatRender = "%." .. precision .. "f" ..
                (variable.unit ~= "" and (" " .. variable.unit:gsub("%%", "%%%%")) or ""),
            disabled = not canEdit,
        })
    if changed then
        pendingVars[variable.name] = math.clamp(fromDisplay(variable, changed), variable.min, variable.max)
        hasVariableChanges = true
    end
end

--- table of variables with subcategory header rows
local function drawVariableTable(id, variables, canEdit)
    if BeginTable(id, {
            { label = "##raceprep-var-name", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
            { label = "##raceprep-var-slider", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
        }, {
            flags = { TABLE_FLAGS.SIZING_STRETCH_PROP, TABLE_FLAGS.ALTERNATE_ROW_BG },
        }) then
        local lastSubCategory
        for _, variable in ipairs(variables) do
            if variable.subCategory ~= "" and variable.subCategory ~= lastSubCategory then
                TableNewRow()
                Text(variable.subCategory, { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
                lastSubCategory = variable.subCategory
            end
            drawVariableRow(variable, canEdit)
        end
        EndTable()
    end
end

local function drawVariableGroup(category, variables, canEdit, height)
    BeginChild("raceprep-tuning-" .. category, {
        size = ImVec2(-1, height),
        outsideSize = true,
        border = true,
    })
    drawVariableTable("raceprep-tuning-table-" .. category, variables, canEdit)
    EndChild()
end

local function drawSetupTab(race)
    local rules = getRules(race)
    local canEdit = canEditSetup(race) and rules.tuning
    updateVariableCache()
    if rules.fuel then
        drawFuelControls(race)
    else
        Text("Fuel", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
        Text("Fuel changes are disabled for this race.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
    end
    Separator()

    Text("Vehicle tuning", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
    if not rules.tuning then
        Text("Tuning changes are disabled for this race.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif not isRaceParticipant(race) then
        Text("Join the grid in the Race tab to set up a car.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif race.isReady() then
        Text("You are ready, so your setup is locked.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif not BJI_Veh.isCurrentVehicleOwn() then
        Text("Choose a car in the Race tab first.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif isConfigForced(race) then
        Text("This race uses a fixed car configuration, so tuning is locked.", {
            color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true,
        })
    elseif not canEdit then
        Text("Tuning cannot be changed in the current race state.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif table.length(variableGroups) == 0 then
        Text("This car has no adjustable tuning settings.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    else
        local scale = getScale()
        local lineHeight = CalcTextSize("Ag").y
        local spacing = GetStyle().ItemSpacing.y
        -- room for the tab row above the list, and the button row plus one
        -- status line below it, so Apply never scrolls out of view
        local footer = 23 * scale + lineHeight + spacing * 4 + 4
        local tabRow = lineHeight + spacing * 3 + 4
        local listHeight = math.max(GetContentRegionAvail().y - footer - tabRow, 140 * scale)

        if BeginTabBar("raceprep-variable-categories", ui_imgui.TabBarFlags_FittingPolicyScroll) then
            local categories = table.keys(variableGroups)
            table.sort(categories)
            for _, category in ipairs(categories) do
                if BeginTabItem(category) then
                    drawVariableGroup(category, variableGroups[category], canEdit, listHeight)
                    EndTabItem()
                end
            end
            EndTabBar()
        end

        if Button("raceprep-apply", "Apply setup (reloads car)", {
                btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS,
                disabled = not hasVariableChanges,
                width = 240,
            }) then
            lastApplyMessage = applySetupVars(race)
        end
        SameLine()
        if Button("raceprep-discard", "Discard changes", {
                btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING,
                disabled = not hasVariableChanges,
                width = 160,
            }) then
            buildVariableGroups()
            lastApplyMessage = nil
        end
    end
    if lastApplyMessage then
        Text(lastApplyMessage, { color = BJI.Utils.Style.TEXT_COLORS.SUCCESS, wrap = true })
    end
end

---------------------------------------------------------------- cooling

local function drawCoolingTab(race)
    updateVariableCache()
    local rules = getRules(race)
    if not BJI_Veh.isCurrentVehicleOwn() then
        Text("Choose a car in the Race tab first.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    if #coolingVariables == 0 then
        Text("No brake cooling settings for this car.", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
        Text("Brake ducts are added by Kagoni Tyre Simulation when the car spawns. If they never appear, " ..
            "that mod's helper is not running for this car (reload the car with Ctrl+R to retry).",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    local canEdit = canEditSetup(race) and rules.tuning
    if not rules.tuning then
        Text("Tuning changes are disabled for this race.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif not canEditSetup(race) then
        Text("Join the grid, choose your car and stay unready to change brake cooling.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
    Text("More cooling keeps brakes from overheating; less lets them reach working temperature faster.",
        { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    drawVariableTable("raceprep-cooling-table", coolingVariables, canEdit)

    local pending = false
    for _, variable in ipairs(coolingVariables) do
        if pendingVars[variable.name] ~= nil then
            pending = true
        end
    end
    if Button("raceprep-cooling-apply", "Apply cooling (reloads car)", {
            btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS,
            disabled = not pending or not canEdit,
            width = 260,
        }) then
        lastApplyMessage = applySetupVars(race)
    end
    if lastApplyMessage then
        Text(lastApplyMessage, { color = BJI.Utils.Style.TEXT_COLORS.SUCCESS, wrap = true })
    end
end

---------------------------------------------------------------- parts and nitrous

local function partsRules()
    local ok, mod = pcall(require, "ge/extensions/raceprep/partsRules")
    return ok and mod or nil
end

--- {short, details} for the driver's own car under the race rules
local function partsCheck(race)
    if frameStamp and frameMemo.parts then
        return frameMemo.parts
    end
    local result = { short = nil, details = {} }
    local veh = BJI_Veh.getCurrentVehicleOwn()
    local mod = partsRules()
    if veh and mod then
        local ok, short, details = pcall(mod.violation, veh:getID(), getRules(race))
        if ok then
            result.short, result.details = short, details or {}
        end
    end
    if frameStamp then
        frameMemo.parts = result
    end
    return result
end

function partsViolation(race)
    return partsCheck(race).short
end

local AID_LABELS = { abs = "ABS", tc = "Traction control", esc = "Stability control" }

function drawPartsAndAids(race)
    local rules = getRules(race)
    local check = partsCheck(race)
    if check.short then
        Text("Parts not allowed in this race:", { color = BJI.Utils.Style.TEXT_COLORS.ERROR })
        for _, line in ipairs(check.details) do
            Text("  " .. line, { color = BJI.Utils.Style.TEXT_COLORS.ERROR, wrap = true })
        end
        Text("Change the parts in the vehicle configuration (or choose another car), then mark ready.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
    local rt = runtime()
    local veh = BJI_Veh.getCurrentVehicleOwn()
    local report = rt and veh and rt.aids and rt.aids[veh:getID()]
    if report then
        local parts = {}
        for _, key in ipairs({ "abs", "tc", "esc" }) do
            local fitted = key == "abs" or report["has" .. key]
            local state = not fitted and "not fitted" or (report[key] and "on" or "off")
            if rules[key] == "on" or rules[key] == "off" then
                state = state .. " (race rule)"
            end
            table.insert(parts, AID_LABELS[key] .. ": " .. state)
        end
        Text("Driving aids:  " .. table.concat(parts, "   "), { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
end

---------------------------------------------------------------- aero

local function aeroIsStock(variable)
    local current = tonumber(pendingVars[variable.name]) or variable.value
    return not variable.default or math.abs(current - variable.default) <= 1e-4 * math.max(1, math.abs(variable.default))
end

--- why the car's applied aero breaks the rules, or nil
local function aeroViolationUncached(race)
    updateVariableCache()
    if getRules(race).aero then
        return nil
    end
    local own=BJI_Veh.getCurrentVehicleOwn()
    if own and core_vehicle_manager then
        local d=core_vehicle_manager.getVehicleData(own:getID())
        if d and d.vdata and d.vdata.raceprepAero then return "aero kit not allowed" end
    end
    for _, variable in ipairs(aeroVariables) do
        if variable.default and math.abs(variable.value - variable.default) > 1e-4 * math.max(1, math.abs(variable.default)) then
            return "aero must be stock"
        end
    end
end

function aeroViolation(race)
    if frameStamp and frameMemo.aero ~= nil then
        return frameMemo.aero or nil
    end
    local result = aeroViolationUncached(race)
    if frameStamp then
        frameMemo.aero = result or false
    end
    return result
end

local function drawAeroTab(race)
    updateVariableCache()
    local rules = getRules(race)
    if not BJI_Veh.isCurrentVehicleOwn() then
        Text("Choose a car in the Race tab first.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    if #aeroVariables == 0 then
        Text("This car has no adjustable aerodynamics.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    local canEdit = canEditSetup(race) and rules.aero
    if not rules.aero then
        Text("Aero changes are disabled for this race; the car must run its stock aero.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    elseif not canEditSetup(race) then
        Text("Join the grid, choose your car and stay unready to change aero.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end

    local scale = getScale()
    local footer = 23 * scale + CalcTextSize("Ag").y * 2 + GetStyle().ItemSpacing.y * 5 + 4
    BeginChild("raceprep-aero-list", {
        size = ImVec2(-1, math.max(GetContentRegionAvail().y - footer, 140 * scale)),
        outsideSize = true,
        border = true,
    })
    drawVariableTable("raceprep-aero-table", aeroVariables, canEdit)
    EndChild()

    local aeroPending = false
    for _, variable in ipairs(aeroVariables) do
        if pendingVars[variable.name] ~= nil then
            aeroPending = true
        end
    end
    if Button("raceprep-aero-apply", "Apply aero (reloads car)", {
            btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS,
            disabled = not aeroPending or not canEditSetup(race),
            width = 240,
        }) then
        lastApplyMessage = applySetupVars(race)
    end
    SameLine()
    local allStock = true
    for _, variable in ipairs(aeroVariables) do
        allStock = allStock and aeroIsStock(variable)
    end
    if Button("raceprep-aero-stock", "Reset aero to stock", {
            btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING,
            disabled = allStock or not canEditSetup(race),
            width = 200,
        }) then
        for _, variable in ipairs(aeroVariables) do
            if variable.default then
                pendingVars[variable.name] = variable.default
            end
        end
        hasVariableChanges = true
    end
    if lastApplyMessage then
        Text(lastApplyMessage, { color = BJI.Utils.Style.TEXT_COLORS.SUCCESS, wrap = true })
    end
end

---------------------------------------------------------------- differential

local MODE_LABELS = {
    open = "Open", lsd = "LSD (race)", locked = "Locked", viscous = "Viscous",
    torqueVectoring = "Torque vectoring", activeLock = "Active lock", dually = "Locked (dually)",
}
local POSITION_LABELS = {
    front = "Front differential",
    rear = "Rear differential",
    centre = "Centre differential",
}
local PRESETS = {
    { key = "race", label = "Race LSD", mode = "lsd", preload = 150, lock = 0.45, coast = 0.25 },
    { key = "drift", label = "Drift", mode = "locked" },
}

local function copySettings(settings)
    local out = {}
    for name, s in pairs(settings or {}) do
        out[name] = {}
        for k, v in pairs(s) do
            out[name][k] = v
        end
    end
    return out
end

local function sameSettings(a, b)
    return serialize(a or {}) == serialize(b or {})
end

-- the front share of a centre diff from its split, and back
local function frontShare(device, split)
    if device.frontOutput == 2 then
        return 1 - split
    end
    return split
end

local function splitFromFrontShare(device, share)
    if device.frontOutput == 2 then
        return 1 - share
    end
    return share
end

--- clamps one vehicle's settings to the race rules
function sanitizeDiff(settings, devices, rules)
    local out = {}
    local byName = {}
    for _, device in ipairs(devices or {}) do
        byName[device.name] = device
    end
    for name, s in pairs(settings or {}) do
        local device = byName[name]
        if device and rules.diff then
            local clean = { mode = s.mode or "stock" }
            if clean.mode ~= "stock" and not (rules.diffModes or {})[clean.mode] then
                clean.mode = "stock"
            end
            if clean.mode == "lsd" then
                local maxLock = (tonumber(rules.maxLock) or 100) / 100
                clean.preload = math.clamp(tonumber(s.preload) or device.preload or 0, 0, tonumber(rules.maxPreload) or 500)
                clean.lock = math.clamp(tonumber(s.lock) or device.lock or 0, 0, maxLock)
                clean.coast = math.clamp(tonumber(s.coast) or device.coast or 0, 0, maxLock)
            end
            if device.position == "centre" and rules.centreSplit and tonumber(s.split) then
                local share = math.clamp(frontShare(device, tonumber(s.split)),
                    tonumber(rules.centreSplitMin) or 0, tonumber(rules.centreSplitMax) or 1)
                clean.split = splitFromFrontShare(device, share)
            end
            if clean.mode ~= "stock" or clean.split then
                out[name] = clean
            end
        end
    end
    return out
end

--- re-applies the driver's diff settings if the rules no longer allow them
local function enforceDiffRules(race, ctxt)
    local rt = runtime()
    local veh = BJI_Veh.getCurrentVehicleOwn()
    if not rt or not veh or ctxt.now < lastRuleCheck + 1000 then
        return
    end
    lastRuleCheck = ctxt.now
    local vid = veh:getID()
    local current = rt.diffSettings[vid]
    local devices = rt.diffReports[vid]
    if current and next(current) and devices then
        local clean = sanitizeDiff(current, devices, getRules(race))
        if not sameSettings(clean, current) then
            rt.applyDiff(vid, clean)
            diffDraftVehicle = nil
            diffMessage = "Your differential was adjusted to match the race rules."
        end
    end
end

-- front-share range allowed for the split variable: the rules' range within
-- what the car's own variable allows
local function splitVarShareRange(device, rules)
    local a = frontShare(device, splitVariable.min)
    local b = frontShare(device, splitVariable.max)
    local lo, hi = math.min(a, b), math.max(a, b)
    lo = math.max(lo, tonumber(rules.centreSplitMin) or 0)
    hi = math.min(hi, tonumber(rules.centreSplitMax) or 1)
    return lo, math.max(lo, hi)
end

local function findCentre(devices)
    for _, device in ipairs(devices or {}) do
        if device.position == "centre" then
            return device
        end
    end
end

--- why the car's applied centre split breaks the rules, or nil
local function splitViolationUncached(race)
    updateVariableCache()
    local rt = runtime()
    local veh = BJI_Veh.getCurrentVehicleOwn()
    if not splitVariable or not rt or not veh then
        return nil
    end
    local centre = findCentre(rt.diffReports[veh:getID()])
    if not centre then
        return nil
    end
    local rules = getRules(race)
    if not rules.diff or not rules.centreSplit then
        if splitVariable.default and math.abs(splitVariable.value - splitVariable.default) > 0.005 then
            return "centre split must be stock"
        end
        return nil
    end
    local lo, hi = splitVarShareRange(centre, rules)
    local share = frontShare(centre, splitVariable.value)
    if share < lo - 0.005 or share > hi + 0.005 then
        return "centre split outside race rules"
    end
end

function splitViolation(race)
    if frameStamp and frameMemo.split ~= nil then
        return frameMemo.split or nil
    end
    local result = splitViolationUncached(race)
    if frameStamp then
        frameMemo.split = result or false
    end
    return result
end

local function drawCentreSplit(device, draft, s, rules, canEdit, canReload)
    TableNewRow()
    Text(device.frontOutput and "Front torque share" or "Output 1 torque share")
    TooltipText(device.frontOutput and "Share of engine torque sent to the front axle." or
        "This car's centre diff outputs could not be matched to front and rear.")
    TableNextColumn()
    if not rules.centreSplit then
        Text("Fixed by the race rules", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
        return
    end
    if splitVariable then
        -- Automation export: the split is a config variable, applied on reload
        local lo, hi = splitVarShareRange(device, rules)
        local current = tonumber(pendingVars[SPLIT_VAR]) or splitVariable.value
        local share = math.clamp(frontShare(device, current), lo, hi) * 100
        local value = SliderFloat("raceprep-diff-splitvar-" .. device.name, share, lo * 100, hi * 100,
            { precision = 0, formatRender = "%.0f %%", disabled = not canReload })
        if value then
            pendingVars[SPLIT_VAR] = math.round(splitFromFrontShare(device, value / 100), 2)
            hasVariableChanges = true
        end
        TableNewRow()
        TableNextColumn()
        Text("Applied with a car reload. Cars with active AWD still shift torque around this value while driving.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    local minShare = (tonumber(rules.centreSplitMin) or 0) * 100
    local maxShare = (tonumber(rules.centreSplitMax) or 1) * 100
    local share = frontShare(device, tonumber(s.split) or device.split or 0.5) * 100
    local value = SliderFloat("raceprep-diff-split-" .. device.name, math.clamp(share, minShare, maxShare),
        minShare, maxShare, { precision = 0, formatRender = "%.0f %%", disabled = not canEdit })
    if value then
        s.split = splitFromFrontShare(device, value / 100)
        draft[device.name] = s
        diffDirty = true
    end
end

local function drawDiffDevice(device, draft, rules, canEdit, canReload)
    local s = draft[device.name] or { mode = "stock" }
    local title = device.uiName or POSITION_LABELS[device.position] or ("Differential " .. device.name)
    Text(title, { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
    SameLine()
    Text(string.var("({1}, stock: {2})", { device.name, MODE_LABELS[device.stockMode] or tostring(device.stockMode) }),
        { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })

    if BeginTable("raceprep-diff-" .. device.name, {
            { label = "##raceprep-diff-label", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
            { label = "##raceprep-diff-value", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        local options = { { value = "stock", label = "Stock (" .. (MODE_LABELS[device.stockMode] or tostring(device.stockMode)) .. ")" } }
        for _, mode in ipairs({ "open", "lsd", "locked" }) do
            if (rules.diffModes or {})[mode] then
                table.insert(options, { value = mode, label = MODE_LABELS[mode] })
            end
        end
        TableNewRow()
        Text("Type")
        TableNextColumn()
        local mode = Combo("raceprep-diff-mode-" .. device.name, s.mode or "stock", options,
            { width = -1, disabled = not canEdit })
        if mode then
            s.mode = mode
            if mode == "lsd" then
                s.preload = s.preload or device.preload or 100
                s.lock = s.lock or device.lock or 0.3
                s.coast = s.coast or device.coast or 0.15
            end
            draft[device.name] = s
            diffDirty = true
        end

        if s.mode == "lsd" then
            local maxLock = tonumber(rules.maxLock) or 100
            TableNewRow()
            Text("Preload")
            TooltipText("Locking torque that is always present, in Nm. Higher = more stable on throttle, more understeer.")
            TableNextColumn()
            local preload = SliderFloat("raceprep-diff-preload-" .. device.name, s.preload or 0, 0,
                tonumber(rules.maxPreload) or 500, { precision = 0, formatRender = "%.0f Nm", disabled = not canEdit })
            if preload then
                s.preload = preload
                diffDirty = true
            end
            TableNewRow()
            Text("Power lock")
            TooltipText("How much the diff locks under throttle.")
            TableNextColumn()
            local lock = SliderFloat("raceprep-diff-lock-" .. device.name, (s.lock or 0) * 100, 0, maxLock,
                { precision = 0, formatRender = "%.0f %%", disabled = not canEdit })
            if lock then
                s.lock = lock / 100
                diffDirty = true
            end
            TableNewRow()
            Text("Coast lock")
            TooltipText("How much the diff locks off throttle and under braking.")
            TableNextColumn()
            local coast = SliderFloat("raceprep-diff-coast-" .. device.name, (s.coast or 0) * 100, 0, maxLock,
                { precision = 0, formatRender = "%.0f %%", disabled = not canEdit })
            if coast then
                s.coast = coast / 100
                diffDirty = true
            end
        end

        if device.position == "centre" then
            drawCentreSplit(device, draft, s, rules, canEdit, canReload)
        end
        EndTable()
    end
end

local function applyPreset(preset, devices, rules, locked)
    local draft = {}
    -- locked devices (no race differential on that axle) keep their current setting
    for name, s in pairs(diffDraft or {}) do
        if locked and locked[name] then draft[name] = s end
    end
    if preset then
        for _, device in ipairs(devices) do
            if not (locked and locked[device.name]) and device.position ~= "centre" and
                (preset.key ~= "drift" or device.position == "rear") then
                draft[device.name] = {
                    mode = preset.mode, preload = preset.preload, lock = preset.lock, coast = preset.coast,
                }
            end
        end
    end
    diffDraft = sanitizeDiff(draft, devices, rules)
    diffDirty = true
end

local function drawDiffTab(race, ctxt)
    local rules = getRules(race)
    local rt = runtime()
    if not rules.diff then
        Text("Differential changes are disabled for this race.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    local veh = BJI_Veh.getCurrentVehicleOwn()
    if not rt or not veh then
        Text("Choose a car in the Race tab first.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    local vid = veh:getID()
    local devices = rt.diffReports[vid]
    if not devices then
        if ctxt.now > lastDiffRequest + 1000 then
            lastDiffRequest = ctxt.now
            rt.requestDiffReport(vid)
        end
        Text("Reading the car's differentials...", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
        return
    end
    if #devices == 0 then
        Text("This car has no differential that can be adjusted.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        return
    end
    if diffDraftVehicle ~= vid then
        diffDraftVehicle = vid
        diffDraft = copySettings(rt.diffSettings[vid])
        diffDirty = false
    end

    updateVariableCache()
    local canEdit = canEditFuel(race)
    local canReload = canEditSetup(race)
    -- race parts unlock their setup: a diff is adjustable only with a race
    -- differential on its axle (Forza style)
    local policy = require("ge/extensions/raceprep/tuningPolicy")
    local vd = core_vehicle_manager and core_vehicle_manager.getVehicleData(vid)
    local locked, lockText = {}, {}
    for _, device in ipairs(devices) do
        local ok, why = policy.raceDifferential(vd and vd.vdata or {}, device.position)
        if not ok then locked[device.name], lockText[device.name] = true, why end
    end
    if next(locked) then
        Text("Differentials without a race differential on their axle keep their stock setup. Fit one in Upgrades.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
    Text("Presets:")
    for _, preset in ipairs(PRESETS) do
        if (rules.diffModes or {})[preset.mode] then
            SameLine()
            if Button("raceprep-diff-preset-" .. preset.key, preset.label,
                    { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO, disabled = not canEdit }) then
                applyPreset(preset, devices, rules, locked)
            end
        end
    end
    SameLine()
    if Button("raceprep-diff-preset-stock", "All stock",
            { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING, disabled = not canEdit }) then
        applyPreset(nil, devices, rules, locked)
    end

    local scale = getScale()
    local footer = 23 * scale + CalcTextSize("Ag").y + GetStyle().ItemSpacing.y * 4 + 4
    BeginChild("raceprep-diff-list", {
        size = ImVec2(-1, math.max(GetContentRegionAvail().y - footer, 140 * scale)),
        outsideSize = true,
        border = true,
    })
    local order = { front = 1, centre = 2, rear = 3, other = 4 }
    local sorted = {}
    for _, device in ipairs(devices) do
        table.insert(sorted, device)
    end
    table.sort(sorted, function(a, b)
        if order[a.position] == order[b.position] then
            return a.name < b.name
        end
        return order[a.position] < order[b.position]
    end)
    for i, device in ipairs(sorted) do
        if i > 1 then
            Separator()
        end
        if lockText[device.name] then
            Text(lockText[device.name], { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
        end
        drawDiffDevice(device, diffDraft, rules, canEdit and not locked[device.name], canReload)
    end
    EndChild()

    local splitPending = pendingVars[SPLIT_VAR] ~= nil
    if Button("raceprep-diff-apply", splitPending and "Apply differential (reloads car)" or "Apply differential", {
            btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS,
            disabled = not canEdit or not (diffDirty or splitPending) or (splitPending and not canReload),
            width = 300,
        }) then
        if diffDirty then
            local clean = sanitizeDiff(diffDraft, devices, rules)
            rt.applyDiff(vid, clean)
            diffDraft = copySettings(clean)
            diffDirty = false
            diffMessage = "Differential applied. No reload needed."
        end
        if splitPending then
            -- reloads the car; the runtime diff settings are re-sent after the respawn
            diffMessage = applySetupVars(race)
        end
    end
    SameLine()
    if Button("raceprep-diff-revert", "Discard changes", {
            btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING,
            disabled = not (diffDirty or splitPending),
            width = 160,
        }) then
        diffDraft = copySettings(rt.diffSettings[vid])
        diffDirty = false
        diffMessage = nil
        pendingVars[SPLIT_VAR] = nil
        hasVariableChanges = next(pendingVars) ~= nil
    end
    if diffMessage then
        Text(diffMessage, { color = BJI.Utils.Style.TEXT_COLORS.SUCCESS, wrap = true })
    end
end

---------------------------------------------------------------- rules (admins)

local function canEditRules()
    return BJI_Perm and BJI_Perm.hasPermission and BJI_Perm.PERMISSIONS and
        BJI_Perm.hasPermission(BJI_Perm.PERMISSIONS.SET_CONFIG) or false
end

local function Checkbox(id, label, value, disabled)
    local ptr = BoolPtr(value == true)
    if ui_imgui.Checkbox(label .. "##" .. id, ptr) and not disabled then
        return ptr[0]
    end
    return nil
end

local GRID_ORDERS = {
    { value = "join", label = "Join order (BeamJoy)" },
    { value = "qualifying", label = "Qualifying result" },
    { value = "reverse", label = "Qualifying, top places reversed" },
    { value = "handicap", label = "Handicap: slowest car (PI) first" },
}
local TRACK_LIMITS = {
    { value = "off", label = "Off" },
    { value = "invalid", label = "Cut laps do not count (no penalty)" },
    { value = "penalty", label = "Cut laps do not count + time penalty" },
}

--- sessions before the race, grid order, track limits; start buttons
function drawSessionRules(race, r, rt)
    Separator()
    Text("Sessions, grid and track limits", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
    if BeginTable("raceprep-rules-sessions", {
            { label = "##raceprep-rs-l", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
            { label = "##raceprep-rs-v", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        TableNewRow()
        Text("Practice")
        TableNextColumn()
        local v = SliderFloat("rules-practice-min", tonumber(r.practiceMinutes) or 0, 0, 60,
            { precision = 0, formatRender = (tonumber(r.practiceMinutes) or 0) < 1 and "none" or "%.0f min" })
        if v then r.practiceMinutes = math.floor(v + 0.5) end
        TableNewRow()
        Text("Qualifying")
        TableNextColumn()
        v = SliderFloat("rules-quali-min", tonumber(r.qualifyingMinutes) or 0, 0, 60,
            { precision = 0, formatRender = (tonumber(r.qualifyingMinutes) or 0) < 1 and "none" or "%.0f min" })
        if v then r.qualifyingMinutes = math.floor(v + 0.5) end
        TableNewRow()
        Text("Race grid")
        TableNextColumn()
        local g = Combo("rules-grid-order", r.gridOrder or "join", GRID_ORDERS, { width = -1 })
        if g then r.gridOrder = g end
        if r.gridOrder == "reverse" then
            TableNewRow()
            Text("Reverse the top")
            TableNextColumn()
            v = SliderFloat("rules-grid-reverse", tonumber(r.gridReverseTop) or 6, 2, 20,
                { precision = 0, formatRender = "%.0f places" })
            if v then r.gridReverseTop = math.floor(v + 0.5) end
        end
        TableNewRow()
        Text("Track limits")
        TableNextColumn()
        local tl = Combo("rules-track-limits", r.trackLimits or "invalid", TRACK_LIMITS, { width = -1 })
        if tl then r.trackLimits = tl end
        if r.trackLimits == "penalty" then
            TableNewRow()
            Text("Free cuts per race")
            TableNextColumn()
            v = SliderFloat("rules-cut-after", tonumber(r.cutPenaltyAfter) or 3, 0, 20, { precision = 0, formatRender = "%.0f" })
            if v then r.cutPenaltyAfter = math.floor(v + 0.5) end
            TableNewRow()
            Text("Penalty per extra cut")
            TableNextColumn()
            v = SliderFloat("rules-cut-seconds", tonumber(r.cutPenaltySeconds) or 5, 1, 30, { precision = 0, formatRender = "%.0f s" })
            if v then r.cutPenaltySeconds = math.floor(v + 0.5) end
        end
        EndTable()
    end
    Text("A cut: every wheel on grass, gravel, sand or dirt (kerbs and asphalt run-off are fine). Handicap uses each car's PI when drivers join the grid.",
        { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })

    local okS, session = pcall(require, "ge/extensions/raceprep/session")
    if not okS or race.raceID == nil then
        return
    end
    local p, q = tonumber(r.practiceMinutes) or 0, tonumber(r.qualifyingMinutes) or 0
    local running = session.data and (session.data.state == "running" or session.data.state == "overtime")
    if running then
        Text(string.format("%s running: %s", session.data.label or "Session", tostring(session.data.raceName)),
            { color = BJI.Utils.Style.TEXT_COLORS.SUCCESS })
        SameLine()
        if Button("raceprep-session-stop-rules", "End it now", { btnStyle = BJI.Utils.Style.BTN_PRESETS.ERROR }) then
            session.stop()
        end
    end
    local function startButton(id, label, kind, enabled)
        if Button(id, label, { btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS, disabled = not enabled }) then
            session.start(kind, race.raceID, p, q)
        end
    end
    if p >= 1 and q >= 1 then
        startButton("raceprep-start-event", string.format("Start practice %d' + qualifying %d'", p, q), "event", true)
        SameLine()
    end
    startButton("raceprep-start-practice", p >= 1 and string.format("Practice only (%d')", p) or "Practice: set minutes", "practice", p >= 1)
    SameLine()
    startButton("raceprep-start-quali", q >= 1 and string.format("Qualifying only (%d')", q) or "Qualifying: set minutes", "qualifying", q >= 1)
    Text("Sessions run in free roam on this race's checkpoints; everyone on the map can join with \"Go to the track\". " ..
        "Start the race here as usual once they are over. Save the rules so the grid order applies.",
        { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
end

local function drawRulesTab(race)
    local rt = runtime()
    if not rt or not rt.isServerManaged() then
        Text("The RacePrep server plugin did not answer, so rules cannot be saved. All options are allowed.",
            { color = BJI.Utils.Style.TEXT_COLORS.ERROR, wrap = true })
        return
    end

    local scopeKey = rulesScope == "race" and tostring(race.raceID) or "default"
    local options = {
        { value = "race", label = "This race: " .. tostring(race.raceName or race.raceID) },
        { value = "default", label = "All races (server default)" },
    }
    Text("Applies to")
    SameLine()
    local scope = Combo("raceprep-rules-scope", rulesScope, options, { width = -1 })
    if scope then
        rulesScope = scope
        rulesDraftKey = nil
        scopeKey = rulesScope == "race" and tostring(race.raceID) or "default"
    end
    if rulesDraftKey ~= scopeKey then
        rulesDraftKey = scopeKey
        rulesDraft = rulesScope == "race" and rt.getRules(race.raceID) or rt.getRules(nil)
    end
    if rulesScope == "race" then
        Text(rt.hasRaceOverride(race.raceID) and "This race has its own rules." or
            "This race uses the server default. Saving creates rules for this race only.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
    Separator()

    local r = rulesDraft
    local changed
    Text("Car class and performance rating", { color = BJI.Utils.Style.TEXT_COLORS.HIGHLIGHT })
    r.allowedClasses = r.allowedClasses or {}
    for i, class in ipairs(rating.classes) do
        if i > 1 then SameLine() end
        changed = Checkbox("rules-class-" .. class, class, r.allowedClasses[class] ~= false)
        if changed ~= nil then r.allowedClasses[class] = changed end
    end
    changed = Checkbox("rules-pi-min", "Minimum PI", r.piMin ~= false and r.piMin ~= nil)
    if changed ~= nil then r.piMin = changed and 100 or false end
    if r.piMin then
        local pi = SliderFloat("rules-pi-min-value", r.piMin, 100, 999, { precision = 0, formatRender = "%.0f PI" })
        if pi then r.piMin = math.floor(pi + 0.5); if r.piMax then r.piMax = math.max(r.piMax, r.piMin) end end
    end
    changed = Checkbox("rules-pi-max", "Maximum PI", r.piMax ~= false and r.piMax ~= nil)
    if changed ~= nil then r.piMax = changed and 999 or false end
    if r.piMax then
        local pi = SliderFloat("rules-pi-max-value", r.piMax, 100, 999, { precision = 0, formatRender = "%.0f PI" })
        if pi then r.piMax = math.floor(pi + 0.5); if r.piMin then r.piMin = math.min(r.piMin, r.piMax) end end
    end
    Text("General PI is used for these limits. Setup sliders do not change PI; installed parts do.",
        { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    Separator()
    changed = Checkbox("rules-tuning", "Allow tuning changes", r.tuning)
    if changed ~= nil then r.tuning = changed end
    changed = Checkbox("rules-fuel", "Allow fuel changes", r.fuel)
    if changed ~= nil then r.fuel = changed end
    Text("Tyre wear (Kagoni Tyre Simulation)")
    SameLine()
    local wear = Combo("rules-tyrewear", r.tyreWear or "driver", {
        { value = "driver", label = "Driver's choice" },
        { value = "on", label = "Always on" },
        { value = "off", label = "Always off" },
    }, { width = -1 })
    if wear then r.tyreWear = wear end
    -- allowed race slick compounds (Ready is blocked on a banned one)
    r.slickCompounds = r.slickCompounds or {}
    Text("Race slick compounds allowed:")
    for _, id in ipairs({ "supersoft", "soft", "medium", "hard" }) do
        SameLine()
        changed = Checkbox("rules-slick-" .. id, ({ supersoft = "Super Soft", soft = "Soft", medium = "Medium", hard = "Hard" })[id],
            r.slickCompounds[id] ~= false)
        if changed ~= nil then r.slickCompounds[id] = changed end
    end
    Text("Start")
    SameLine()
    local start = Combo("rules-starttype", r.startType or "standing", {
        { value = "standing", label = "Standing start (BeamJoy)" },
        { value = "rolling", label = "Rolling start (pace-limited formation)" },
    }, { width = -1 })
    if start then r.startType = start end
    if r.startType == "rolling" then
        Indent()
        local pace = SliderFloat("rules-pacespeed", tonumber(r.paceSpeed) or 80, 40, 150,
            { precision = 0, formatRender = "Pace %.0f km/h" })
        if pace then r.paceSpeed = pace end
        Text("Cars are held to the pace speed after the countdown; green when the first car reaches checkpoint 1. Lap 1 includes the formation run.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        Unindent()
    end
    Text('Rubber and wind are track settings now: Race Prep menu (top bar) > Track settings.',{color=BJI.Utils.Style.TEXT_COLORS.DISABLED,wrap=true})
    changed=Checkbox("rules-safety","Update safety rating after this race",r.safetyRating or false)
    if changed~=nil then r.safetyRating=changed end
    changed=Checkbox("rules-yellowflags","Automatic yellow flags for stopped cars",r.yellowFlags or false)
    if changed~=nil then r.yellowFlags=changed end
    changed=Checkbox("rules-startlights","Start lights / allow jump starts in final 5 seconds",r.startLights or false)
    if changed~=nil then r.startLights=changed end
    if r.startLights then
        local penalty=SliderFloat("rules-false-start",tonumber(r.falseStartPenaltySeconds) or 0,0,60,{precision=0,
            formatRender=(tonumber(r.falseStartPenaltySeconds) or 0)<1 and "Jump start: tagged in results only" or "Jump start: tagged +%.0f s"})
        if penalty then r.falseStartPenaltySeconds=penalty end
        Text("Standing starts: early movement beyond 0.75 m adds a time penalty. Rolling starts retain their formation procedure.",{color=BJI.Utils.Style.TEXT_COLORS.DISABLED,wrap=true})
    end
    if Button('rp-series-add-round','Add this race to championship schedule',{btnStyle=BJI.Utils.Style.BTN_PRESETS.INFO}) then
        require('ge/extensions/raceprep/director').championship('addRound',{raceID=race.raceID,
            level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()})
    end
    if Button('rp-open-control' ,'Race control / driver statistics',{btnStyle=BJI.Utils.Style.BTN_PRESETS.INFO}) then
        require('ge/extensions/raceprep/director').show=true
    end
    drawSessionRules(race, r, rt)
    if not rt.hasRoadTemperature() then
        Text("Track temperature is not available yet (it starts once a map is loaded).",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
    changed = Checkbox("rules-tracktemp", "Fixed track temperature (off = follows sun, cloud and air)", r.trackTempFixed)
    if changed ~= nil then r.trackTempFixed = changed end
    if r.trackTempFixed then
        Indent()
        local t = SliderFloat("rules-tracktemp-value", tonumber(r.trackTemp) or 30, 0, 70,
            { precision = 0, formatRender = "%.0f \194\176C" })
        if t then r.trackTemp = t end
        Unindent()
    end
    Separator()
    Text("Parts")
    r.parts = type(r.parts) == "table" and r.parts or {}
    local mod = partsRules()
    if mod and BeginTable("raceprep-rules-parts", {
            { label = "##raceprep-rules-parts-label", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
            { label = "##raceprep-rules-parts-value", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        for _, c in ipairs(mod.CATEGORIES) do
            TableNewRow()
            Text(c.label)
            TableNextColumn()
            local v = Combo("rules-parts-" .. c.key, r.parts[c.key] or "any", {
                { value = "any", label = "Any parts" },
                { value = "stock", label = "Factory parts only" },
            }, { width = -1 })
            if v then r.parts[c.key] = v end
        end
        EndTable()
    end
    changed = Checkbox("rules-nitrous", "Allow nitrous", r.nitrous ~= false)
    if changed ~= nil then r.nitrous = changed end
    Text("Driving aids")
    if BeginTable("raceprep-rules-aids", {
            { label = "##raceprep-rules-aids-label", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
            { label = "##raceprep-rules-aids-value", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        for _, key in ipairs({ "abs", "tc", "esc" }) do
            TableNewRow()
            Text(AID_LABELS[key])
            TableNextColumn()
            local v = Combo("rules-aid-" .. key, r[key] or "driver", {
                { value = "driver", label = "Driver's choice" },
                { value = "on", label = "Forced on (where fitted)" },
                { value = "off", label = "Forced off" },
            }, { width = -1 })
            if v then r[key] = v end
        end
        EndTable()
    end
    Separator()
    changed = Checkbox("rules-aero", "Allow aero changes (off = stock aero required)", r.aero)
    if changed ~= nil then r.aero = changed end
    changed = Checkbox("rules-diff", "Allow differential changes", r.diff)
    if changed ~= nil then r.diff = changed end

    if r.diff then
        Indent()
        Text("Allowed differential types:")
        r.diffModes = r.diffModes or {}
        for _, mode in ipairs({ "open", "lsd", "locked" }) do
            SameLine()
            changed = Checkbox("rules-mode-" .. mode, MODE_LABELS[mode], r.diffModes[mode])
            if changed ~= nil then r.diffModes[mode] = changed end
        end
        if BeginTable("raceprep-rules-limits", {
                { label = "##raceprep-rules-label", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
                { label = "##raceprep-rules-value", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
            }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
            TableNewRow()
            Text("Max LSD preload")
            TableNextColumn()
            local v = SliderFloat("rules-maxPreload", tonumber(r.maxPreload) or 500, 0, 2000,
                { precision = 0, formatRender = "%.0f Nm" })
            if v then r.maxPreload = v end
            TableNewRow()
            Text("Max LSD lock")
            TableNextColumn()
            v = SliderFloat("rules-maxLock", tonumber(r.maxLock) or 100, 0, 100,
                { precision = 0, formatRender = "%.0f %%" })
            if v then r.maxLock = v end
            EndTable()
        end
        changed = Checkbox("rules-split", "Allow centre diff torque split changes", r.centreSplit)
        if changed ~= nil then r.centreSplit = changed end
        if r.centreSplit and BeginTable("raceprep-rules-split", {
                { label = "##raceprep-rules-split-label", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.42 },
                { label = "##raceprep-rules-split-value", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH }, width = 0.58 },
            }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
            TableNewRow()
            Text("Front share, minimum")
            TableNextColumn()
            local v = SliderFloat("rules-splitMin", (tonumber(r.centreSplitMin) or 0) * 100, 0, 100,
                { precision = 0, formatRender = "%.0f %%" })
            if v then r.centreSplitMin = math.min(v / 100, tonumber(r.centreSplitMax) or 1) end
            TableNewRow()
            Text("Front share, maximum")
            TableNextColumn()
            v = SliderFloat("rules-splitMax", (tonumber(r.centreSplitMax) or 1) * 100, 0, 100,
                { precision = 0, formatRender = "%.0f %%" })
            if v then r.centreSplitMax = math.max(v / 100, tonumber(r.centreSplitMin) or 0) end
            EndTable()
        end
        Unindent()
    end
    Separator()

    if Button("raceprep-rules-save", "Save rules", { btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS, width = 160 }) then
        rt.sendRules(rulesScope == "race" and race.raceID or "default", r)
        rulesDraftKey = nil
    end
    if rulesScope == "race" and rt.hasRaceOverride(race.raceID) then
        SameLine()
        if Button("raceprep-rules-clear", "Use server default for this race",
                { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING }) then
            rt.sendRules(race.raceID, nil)
            rulesDraftKey = nil
        end
    end
    if rt.rulesStatus then
        Text(rt.rulesStatus, { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    end
    Text("Limits are checked by each driver's game when they set up their car.",
        { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
end

local AID_TEXT = { driver = "driver's choice", on = "forced on", off = "forced off" }

--- what the race rules are, for every driver (editing is in BeamJoy's Race
--- Settings window when the race is started)
function drawRulesSummary(race)
    local r = getRules(race)
    local rt = runtime()
    local lines = {}
    local function add(label, value) table.insert(lines, { label, value }) end
    local classes = {}
    local allClasses = true
    for _, c in ipairs({ "E", "D", "C", "B", "A", "S", "R", "P", "X" }) do
        if not r.allowedClasses or r.allowedClasses[c] ~= false then table.insert(classes, c) else allClasses = false end
    end
    add("Car classes", allClasses and "all" or table.concat(classes, ", "))
    if r.piMin or r.piMax then
        add("PI range", string.format("%s - %s", r.piMin or "any", r.piMax or "any"))
    end
    local parts = {}
    for _, key in ipairs({ "engine", "drivetrain", "suspension", "tyres" }) do
        if type(r.parts) == "table" and r.parts[key] == "stock" then table.insert(parts, key) end
    end
    add("Parts", #parts == 0 and "any" or ("factory only: " .. table.concat(parts, ", ")))
    add("Nitrous", r.nitrous == false and "banned" or "allowed")
    add("ABS / TC / ESC", string.format("%s / %s / %s", AID_TEXT[r.abs or "driver"], AID_TEXT[r.tc or "driver"], AID_TEXT[r.esc or "driver"]))
    add("Start", r.startType == "rolling" and string.format("rolling, pace %d km/h", math.floor(tonumber(r.paceSpeed) or 80)) or "standing")
    add("Tuning / fuel / aero / diff", string.format("%s / %s / %s / %s", r.tuning ~= false and "allowed" or "no",
        r.fuel ~= false and "allowed" or "no", r.aero ~= false and "allowed" or "stock", r.diff ~= false and "allowed" or "no"))
    add("Tyre wear (KTS)", r.tyreWear == "on" and "always on" or r.tyreWear == "off" and "always off" or "driver's choice")
    local slicks, allSlicks = {}, true
    for _, id in ipairs({ "supersoft", "soft", "medium", "hard" }) do
        if type(r.slickCompounds) ~= "table" or r.slickCompounds[id] ~= false then
            table.insert(slicks, ({ supersoft = "Super Soft", soft = "Soft", medium = "Medium", hard = "Hard" })[id])
        else allSlicks = false end
    end
    add("Race slicks", allSlicks and "any compound" or (#slicks == 0 and "none allowed" or table.concat(slicks, ", ") .. " only"))
    local sessions = {}
    if (tonumber(r.practiceMinutes) or 0) >= 1 then table.insert(sessions, string.format("practice %d min", r.practiceMinutes)) end
    if (tonumber(r.qualifyingMinutes) or 0) >= 1 then table.insert(sessions, string.format("qualifying %d min", r.qualifyingMinutes)) end
    add("Sessions", #sessions == 0 and "race only" or (table.concat(sessions, ", ") .. ", race"))
    for _, o in ipairs(GRID_ORDERS) do
        if o.value == (r.gridOrder or "join") then
            add("Grid", o.label .. (r.gridOrder == "reverse" and string.format(" (top %d)", tonumber(r.gridReverseTop) or 6) or ""))
        end
    end
    if Button('rp-driver-control','Race control / driver statistics',{btnStyle=BJI.Utils.Style.BTN_PRESETS.INFO}) then
        require('ge/extensions/raceprep/director').show=true
    end
    add('Start lights',r.startLights and ((tonumber(r.falseStartPenaltySeconds) or 0)<1 and 'jump start tagged in results' or
        string.format('jump start tagged +%g s',r.falseStartPenaltySeconds)) or 'BeamJoy default')
    add('Yellow flags',r.yellowFlags and 'automatic stopped-car hazards' or 'manual only')
    add('Safety rating',r.safetyRating and 'updated after race' or 'statistics only')
    do
        local tr=(require('ge/extensions/raceprep/director').data or {}).track
        if tr and tr.rubber and tr.rubber.enabled then add('Rubber (track)',string.format('%d%%',math.floor((tonumber(tr.amount) or 0)*100+.5))) end
        if tr and tr.wind and tr.wind.enabled then add('Wind (track)',string.format('%g km/h, gust +/- %g',tr.wind.speedKmh or 0,tr.wind.gustKmh or 0)) end
    end
    add("Track limits", r.trackLimits == "off" and "off" or r.trackLimits == "penalty" and
        string.format("cut laps invalid; +%ds per cut after %d", tonumber(r.cutPenaltySeconds) or 5, tonumber(r.cutPenaltyAfter) or 3) or
        "cut laps invalid")
    if r.trackTempFixed then add("Track temperature", string.format("fixed %d C", math.floor(tonumber(r.trackTemp) or 30))) end
    if BeginTable("raceprep-rules-summary", {
            { label = "##rs-l", flags = { TABLE_COLUMNS_FLAGS.WIDTH_FIXED } },
            { label = "##rs-v", flags = { TABLE_COLUMNS_FLAGS.WIDTH_STRETCH } },
        }, { flags = { TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        for _, l in ipairs(lines) do
            TableNewRow()
            Text(l[1], { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
            TableNextColumn()
            Text(l[2])
        end
        EndTable()
    end
    Text((rt and rt.hasRaceOverride and rt.hasRaceOverride(race.raceID)) and "This race has its own rules." or
        "This race uses the server default rules.", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
    if canEditRules() then
        Text("Admins: the rules can also be set in BeamJoy's Race Settings window when starting a race.",
            { color = BJI.Utils.Style.TEXT_COLORS.DISABLED, wrap = true })
        if Button("raceprep-rules-edit-toggle", rulesEditorOpen and "Close rules editor" or "Edit rules",
                { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO, width = 200 }) then
            rulesEditorOpen = not rulesEditorOpen
        end
        if rulesEditorOpen then
            Separator()
            drawRulesTab(race)
        end
    end
end

local function body(ctxt)
    if frameStamp ~= ctxt.now then
        frameStamp = ctxt.now
        frameMemo = {}
    end
    concealStockGridWindow()
    local race = getRace()
    if not race then
        return
    end

    enforceDiffRules(race, ctxt)
    drawCountdown(race, ctxt)
    if BeginTabBar("raceprep-main-tabs") then
        if BeginTabItem("Race") then
            drawRaceTab(race, ctxt)
            EndTabItem()
        end
        if BeginTabItem(hasVariableChanges and "Setup *" .. "###raceprep-setup-tab" or "Setup###raceprep-setup-tab") then
            drawSetupTab(race)
            EndTabItem()
        end
        if BeginTabItem("Cooling###raceprep-cooling-tab") then
            drawCoolingTab(race)
            EndTabItem()
        end
        if BeginTabItem("Aero###raceprep-aero-tab") then
            drawAeroTab(race)
            EndTabItem()
        end
        if BeginTabItem(diffDirty and "Diff *###raceprep-diff-tab" or "Diff###raceprep-diff-tab") then
            drawDiffTab(race, ctxt)
            EndTabItem()
        end
        if BeginTabItem("Rules") then
            drawRulesSummary(race)
            EndTabItem()
        end
        EndTabBar()
    end
end

local function reset()
    pendingVars = {}
    variableVehicleID = nil
    variableSignature = nil
    variableGroups = {}
    hasVariableChanges = false
    lastApplyMessage = nil
    fuelTargets = {}
    diffDraft = {}
    diffDraftVehicle = nil
    diffDirty = false
    diffMessage = nil
    rulesDraft = nil
    rulesDraftKey = nil
end

W.getState = function()
    concealStockGridWindow()
    setWindowTitle()
    return getRace() ~= nil
end

W.onLoad = reset
W.onUnload = reset
W.body = body
-- the rules editor, drawn inside BeamJoy's Race Settings window (bjiRacePrep)
W.drawRulesEditor = function(raceID, raceName)
    if canEditRules() then
        local scroll=type(BeginChild)=='function' and type(EndChild)=='function'
        if scroll then
            local avail=GetContentRegionAvail and GetContentRegionAvail().y or 420
            -- fills the window: grows when the window is made bigger
            BeginChild('raceprep-rules-scroll',{size=ImVec2(-1,math.max(180,avail-12)),outsideSize=true,border=true})
        end
        drawRulesTab({ raceID = raceID, raceName = raceName })
        if scroll then EndChild() end
    end
end
W.canEditRules = canEditRules

return W
