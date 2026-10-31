-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- RacePrep add-on runtime (GE side).
--
-- 1. Registers the RacePrep, RaceHUD and RaceTower windows with BeamJoy.
--    BeamJoy scans /lua/ge/extensions/BJI/ui/windows once, inside its own
--    onExtensionLoaded. BeamMP mounts server mods one by one, so this add-on can
--    be mounted after that scan (observed: BJI finished at 220.20s, this ZIP
--    mounted at 220.44s) and the window would never load. This extension waits
--    for BeamJoy's window manager and registers the window the same way
--    WindowsManager.register does. If BeamJoy's scan already picked it up, it
--    does nothing.
-- 2. Keeps the race-prep rules sent by the server plugin (Server/RacePrep).
-- 3. Shows the track temperature (built-in roadTemperature) and applies
--    the race rule that fixes it.
-- 4. Talks to the vehicle-side raceprepDiff extension, and re-sends the
--    driver's differential settings after the car respawns.
-- 5. Applies the race rules for tyre wear and driving aids (ABS, traction and
--    stability control) to the driver's car.
-- 6. Collects race results (raceprep/results) and sends them to the server
--    for the race history; the RaceResults window shows them.
-- 7. Practice / qualifying sessions and track limits (raceprep/session); the
--    RaceSession window shows them.

local M = {}

local WINDOWS = {
    { name = "RaceControl", path = "ge/extensions/BJI/ui/windows/RaceControl" },
    { name = "RacePrep", path = "ge/extensions/BJI/ui/windows/RacePrep" },
    { name = "RaceHUD", path = "ge/extensions/BJI/ui/windows/RaceHUD" },
    { name = "RaceTower", path = "ge/extensions/BJI/ui/windows/RaceTower" },
    { name = "RaceResults", path = "ge/extensions/BJI/ui/windows/RaceResults" },
    { name = "RaceSession", path = "ge/extensions/BJI/ui/windows/RaceSession" },
    { name = "RaceTrack", path = "ge/extensions/BJI/ui/windows/RaceTrack" },
    { name = "RaceUpgrades", path = "ge/extensions/BJI/ui/windows/RaceUpgrades" },
}
local HANDLER_SOURCE = "bjiRacePrep"

-- used when the server has no RacePrep plugin: everything allowed
M.DEFAULT_RULES = {
    targetClass = "",
    tuning = true,
    fuel = true,
    aero = true,
    diff = true,
    diffModes = { open = true, lsd = true, locked = true },
    centreSplit = true,
    centreSplitMin = 0.2,
    centreSplitMax = 0.8,
    maxPreload = 500,
    maxLock = 100,
    trackTempFixed = false,
    trackTemp = 30,
    tyreWear = "driver", -- Kagoni Tyre Simulation wear: "driver" (own choice), "on", "off"
    -- start: "standing" (BeamJoy's own) or "rolling" (pace-limited formation
    -- from the grid; green when the first car reaches checkpoint 1)
    startType = "standing",
    rubberBuildUp = false, rubberInitial = 20, rubberBuildKm = 50, rubberDryBonus = 3, rubberWetPenalty = 5,
    windEnabled = false, windSpeedKmh = 15, windDirection = 0, windGustKmh = 5, windGustPeriod = 12,
    safetyRating = false,
    minSkill = 0, minSafety = "", minLicence = "", seriesName = "", specModel = "", specConfig = "",
    yellowFlags = false,
    startLights = false, falseStartPenaltySeconds = 0, falseStartTolerance = .75,
    paceSpeed = 80,
    allowedClasses = { E=true, D=true, C=true, B=true, A=true, S=true, R=true, P=true, X=true },
    -- race slick compounds allowed in the race (Ready is blocked otherwise)
    slickCompounds = { supersoft = true, soft = true, medium = true, hard = true },
    piMin = false,
    piMax = false,
    -- per part group: "any" or "stock" (factory parts only); see raceprep/partsRules
    parts = { engine = "any", drivetrain = "any", suspension = "any", tyres = "any", body = "any" },
    -- upgrade caps (raceprep/upgradeRules): most permissive by default
    upgrades = { engine = "race", induction = "allow", engineConversion = true, drivetrainConversion = "any",
        compound = "slick", width = 40, weight = "race", brakes = "race", radiators = true },
    nitrous = true,
    -- driving aids: "driver" (own choice), "on" (forced on where fitted), "off"
    abs = "driver",
    tc = "driver",
    esc = "driver",
    -- sessions before the race (minutes, 0 = none) and the grid order:
    -- "join" (BeamJoy), "qualifying", "reverse" (top N reversed), "handicap"
    practiceMinutes = 0,
    qualifyingMinutes = 0,
    gridOrder = "join",
    gridReverseTop = 6,
    -- track limits (all wheels off the track): "off", "invalid" (lap does not
    -- count), "penalty" (also seconds added after cutPenaltyAfter cuts)
    trackLimits = "invalid",
    cutPenaltyAfter = 3,
    cutPenaltySeconds = 5,
}

---@type {default: table, races: table<string, table>}?
M.rules = nil
-- driver skill ratings from the server: playerID (string) -> {rating, races, delta}
M.skills = {}

--- "1532" style skill text for a player, or nil
M.skillText = function(playerID, withDelta)
    local s = M.skills and M.skills[tostring(playerID)]
    if not s or not tonumber(s.rating) then
        return nil
    end
    local text = string.format("%d", math.floor(s.rating + 0.5))
    if (tonumber(s.races) or 0) < 5 then
        text = text .. "?" -- provisional
    end
    if withDelta and tonumber(s.delta) then
        text = text .. string.format(" (%+.1f)", s.delta)
    end
    return text
end
M.rulesStatus = nil -- last message from the server (saved / denied)

-- game vehicle id -> list of diff devices reported by the vehicle
M.diffReports = {}
-- game vehicle id -> table<deviceName, settings> chosen by the driver
M.diffSettings = {}

-- the window list of the BeamJoy instance we last handled; BeamJoy builds a
-- new one each time it loads (e.g. on reconnect)
local handledWindows
local handlersRegistered = false
-- game vehicle id -> time (s) to re-send diff settings after a respawn
local pendingReapply = {}
local clock = 0

local function log(level, msg)
    if type(_G.log) == "function" then
        _G.log(level, "bjiRacePrep", msg)
    end
end

local function beamJoyReady()
    if Platform.isBJR() then return false end
    local bji = Platform.get("BJI")
    local manager = Platform.get("BJI_Windows")
    local context = Platform.get("BJI_Context")
    -- BJI.Windows.Race is set during WindowsManager's own scan, so its
    -- presence means the scan has finished
    return bji and bji.Windows and bji.Windows.Race and
        manager and manager.windows and manager.showStates and
        context and context.GUI and context.GUI.registerWindow
end

local function registerWindow(windowName, windowPath)
    local manager = BJI_Windows
    local existing
    for _, w in pairs(manager.windows) do
        if type(w) == "table" and w.name == windowName then
            existing = w
            break
        end
    end

    -- a previous BeamJoy instance may have left a stale module behind
    package.loaded[windowPath] = nil
    local ok, w = pcall(require, windowPath)
    if not ok or type(w) ~= "table" or not w.getState or not w.body then
        log("E", "Could not load the " .. windowName .. " window: " .. tostring(w))
        return false
    end

    if existing then
        -- BeamJoy may have scanned this window before register() reset the
        -- shared modules. Refresh its closures in place so the manager's
        -- references and saved layout remain valid, using current session state.
        for key, value in pairs(w) do existing[key] = value end
        _G["BJI_Win_" .. windowName] = existing
        BJI.Windows[windowName] = existing
        return true
    end

    if manager.windows.insert then
        manager.windows:insert(w)
    else
        table.insert(manager.windows, w)
    end
    manager.showStates[w.name] = false
    BJI_Context.GUI.registerWindow(w.name, w.size or w.minSize)
    _G["BJI_Win_" .. w.name] = w
    BJI.Windows[w.name] = w
    log("I", "BJI_Win_" .. w.name .. " loaded (late registration)")
    return true
end

local function register()
    -- a fresh BeamJoy instance gets fresh timing state too
    package.loaded["ge/extensions/raceprep/timing"] = nil
    package.loaded["ge/extensions/raceprep/racePath"] = nil
    package.loaded["ge/extensions/raceprep/partsRules"] = nil
    local oldRubber=package.loaded['ge/extensions/raceprep/raceRubber']
    if oldRubber and oldRubber.restore then oldRubber.restore() end
    package.loaded['ge/extensions/raceprep/raceRubber']=nil
    local line=package.loaded['ge/extensions/raceprep/rubberLine']
    if line then line.restore();line.clear() end
    local surface=package.loaded['ge/extensions/raceprep/rubberSurface']
    if surface then surface.restore() end
    local oldEnvironment = package.loaded["ge/extensions/raceprep/raceEnvironment"]
    if oldEnvironment and oldEnvironment.restore then oldEnvironment.restore() end
    package.loaded["ge/extensions/raceprep/raceEnvironment"] = nil
    local oldWeather = package.loaded["ge/extensions/raceprep/weather"]
    if oldWeather and oldWeather.restore then oldWeather.restore() end
    package.loaded["ge/extensions/raceprep/weather"] = nil
    package.loaded["ge/extensions/raceprep/director"] = nil
    package.loaded["ge/extensions/raceprep/session"] = nil
    package.loaded["ge/extensions/raceprep/lapTracker"] = nil
    package.loaded["ge/extensions/raceprep/upgrades"] = nil
    local all = true
    for _, def in ipairs(WINDOWS) do
        all = registerWindow(def.name, def.path) and all
    end
    return all
end

---------------------------------------------------------------- rules

local function onRules(data)
    local ok, decoded = pcall(jsonDecode, data)
    if ok and type(decoded) == "table" then
        decoded.default = type(decoded.default) == "table" and decoded.default or {}
        decoded.races = type(decoded.races) == "table" and decoded.races or {}
        M.rules = decoded
    else
        log("W", "Ignoring invalid rules from server: " .. tostring(data))
    end
end

local function registerHandlers()
    if type(rawget(_G, 'AddEventHandler'))~='function' and not require('ge/extensions/raceprep/frontend').isCareer() then
        return false
    end
    require('ge/extensions/raceprep/net').on("RacePrepRules", onRules, HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on("RacePrepSkills", function(data)
        local ok, decoded = pcall(jsonDecode, data)
        if ok and type(decoded) == "table" then
            M.skills = decoded
        end
    end, HANDLER_SOURCE)
    -- Motorsport settings: permissions by BeamJoy group, race weekend defaults,
    -- and what this player may do ({settings, groups, abilities, group})
    require('ge/extensions/raceprep/net').on("RacePrepMotorsport", function(data)
        local ok, decoded = pcall(jsonDecode, data)
        if ok and type(decoded) == "table" then M.motorsport = decoded end
    end, HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on("RacePrepRulesStatus", function(data)
        M.rulesStatus = tostring(data or "")
    end, HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on("RacePrepControl", function(data) require("ge/extensions/raceprep/director").onState(data) end, HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on('RacePrepMarbleReset',function(level) require('ge/extensions/raceprep/rubberMarbles').onReset(level) end,HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on('RacePrepMarbleDelta',function(wire) require('ge/extensions/raceprep/rubberMarbles').onDelta(wire) end,HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on('RacePrepRubberReset',function(level) require('ge/extensions/raceprep/rubberLine').onReset(level) end,HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on('RacePrepRubberDelta',function(wire) require('ge/extensions/raceprep/rubberLine').onDelta(wire) end,HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on("RacePrepAdminStatus", function(data)
        local director = require("ge/extensions/raceprep/director")
        director.adminStatus, director.adminStatusSeq = tostring(data), (director.adminStatusSeq or 0) + 1
    end, HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on("RacePrepSession", function(data)
        local ok, session = pcall(require, "ge/extensions/raceprep/session")
        if ok then session.onSession(data) end
    end, HANDLER_SOURCE)
    require('ge/extensions/raceprep/net').on("RacePrepCut", function(data)
        local ok, p = pcall(jsonDecode, data)
        local rok, results = pcall(require, "ge/extensions/raceprep/results")
        if ok and type(p) == "table" and rok then results.onCut(p.playerID, p.raceID, p.lap) end
    end, HANDLER_SOURCE)
    return true
end

-- The rules request must go out after the game's connection to the server
-- is up: sent right after this add-on loads, it was lost (seen 2026-10-12).
-- Ask once BeamJoy reports the client connected, and repeat until answered.
local RULES_RETRY_S = 3
local nextRulesRequest = 0
local function requestRulesWhenConnected()
    if M.rules or not handlersRegistered or clock < nextRulesRequest then
        return
    end
    local bji = Platform.get("BJI")
    local network = rawget(_G, "MPGameNetwork")
    local connected = bji and bji.CLIENT_READY and
        (not network or not network.launcherConnected or network.launcherConnected())
    if connected and (require("ge/extensions/raceprep/frontend").isCareer() or type(rawget(_G, "TriggerServerEvent")) == "function") then
        nextRulesRequest = clock + RULES_RETRY_S
        require('ge/extensions/raceprep/net').send("RacePrepGetRules", "")
        require('ge/extensions/raceprep/net').send("RacePrepGetSkills", "")
        require('ge/extensions/raceprep/net').send("RacePrepGetSession", "")
        require('ge/extensions/raceprep/net').send("RacePrepGetMotorsport", "")
    end
end

local function copyInto(target, source)
    for k, v in pairs(source or {}) do
        if type(v) == "table" then
            target[k] = target[k] or {}
            copyInto(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

--- effective rules for a race: built-in defaults < server default < race override
---@param raceID any?
M.getRules = function(raceID)
    local active=Platform.isBJR() and beamjoy_raceRunner and beamjoy_raceRunner.session
    local selected=active and (raceID==nil or tostring(raceID)==tostring(active.raceId)) and M.presetSessions and M.presetSessions[tostring(active.id)]
    if selected then return copyInto({},selected.rules) end
    local out = copyInto({}, M.DEFAULT_RULES)
    if M.rules then
        copyInto(out, M.rules.default)
        if raceID ~= nil then
            local scope=Platform.isBJR() and (tostring(getCurrentLevelIdentifier())..":"..tostring(raceID)) or tostring(raceID)
            copyInto(out, M.rules.races[scope])
        end
    end
    return out
end

--- true when this race has its own override on the server
M.hasRaceOverride = function(raceID)
    local scope=Platform.isBJR() and (tostring(getCurrentLevelIdentifier())..":"..tostring(raceID)) or tostring(raceID)
    return M.rules ~= nil and raceID ~= nil and M.rules.races[scope] ~= nil
end

M.isServerManaged = function()
    return M.rules ~= nil
end

--- scope: "default" or a race id; rules: table, or nil to clear a race override
M.sendRules = function(scope, rules)
    if (not require("ge/extensions/raceprep/frontend").isCareer() and type(rawget(_G, "TriggerServerEvent")) ~= "function") then
        M.rulesStatus = "Not connected to a BeamMP server."
        return
    end
    M.rulesStatus = "Saving..."
    require('ge/extensions/raceprep/net').send("RacePrepSetRules", jsonEncode({ scope = tostring(scope), rules = rules }))
end

---------------------------------------------------------------- diff

local function getVehicle(gameVehID)
    if not gameVehID then
        return nil
    end
    -- main.lua's own lookup; be:getObjectByID as a fallback
    if type(rawget(_G, "getObjectByID")) == "function" then
        return getObjectByID(gameVehID)
    end
    return be:getObjectByID(gameVehID)
end

M.requestDiffReport = function(gameVehID)
    local veh = getVehicle(gameVehID)
    if veh then
        veh:queueLuaCommand('extensions.load("raceprepDiff") if raceprepDiff then raceprepDiff.report() end')
    end
end

M.applyDiff = function(gameVehID, settings)
    local veh = getVehicle(gameVehID)
    if not veh then
        return
    end
    M.diffSettings[gameVehID] = settings or {}
    veh:queueLuaCommand(string.format(
        'extensions.load("raceprepDiff") if raceprepDiff then raceprepDiff.applyAll(%s) end',
        serialize(M.diffSettings[gameVehID])))
end

-- called from the vehicle VM
M.onDiffReport = function(gameVehID, devices)
    M.diffReports[gameVehID] = type(devices) == "table" and devices or {}
    if M.diffSettings[gameVehID] then
        local present = {}
        for _, d in ipairs(M.diffReports[gameVehID]) do if d.name then present[d.name] = true end end
        for name in pairs(M.diffSettings[gameVehID]) do
            if not present[name] then M.diffSettings[gameVehID][name] = nil end
        end
    end
end

M.onVehicleSpawned = function(gameVehID)
    local line=package.loaded['ge/extensions/raceprep/rubberLine']
    if line then line.vehicleChanged(gameVehID) end
    -- a respawn (e.g. Apply setup) reloads the vehicle VM and its diff state
    M.diffReports[gameVehID] = nil
    if M.diffSettings[gameVehID] and next(M.diffSettings[gameVehID]) then
        pendingReapply[gameVehID] = clock + 1
    end
end

M.onVehicleDestroyed = function(gameVehID)
    local line=package.loaded['ge/extensions/raceprep/rubberLine']
    if line then line.vehicleChanged(gameVehID) end
    M.diffReports[gameVehID] = nil
    M.diffSettings[gameVehID] = nil
    pendingReapply[gameVehID] = nil
    M.aids[gameVehID] = nil
end

M.onVehicleResetted=function(gameVehID)
    local line=package.loaded['ge/extensions/raceprep/rubberLine']
    if line then line.vehicleChanged(gameVehID) end
end

---------------------------------------------------------------- track temperature
-- Track temperature comes from the built-in roadTemperature extension
-- (formerly a separate mod), which also feeds the tyre mod. Race Prep shows it
-- and applies the race rule "Fixed track temperature" through
-- roadTemperature.setFixed.

M.trackTemp = nil -- copy of roadTemperature.get(), for the windows
local nextTrackCheck = 0
local fixedByRules = false

local function currentRaceID()
    local scenario = Platform.get("BJI_Scenario")
    if scenario and scenario.TYPES and scenario.TYPES.RACE_MULTI then
        local race = scenario.get(scenario.TYPES.RACE_MULTI)
        if race and race.state then
            return race.raceID
        end
    end
end

local function releaseFixed(road)
    if fixedByRules and road and road.setFixed then
        road.setFixed(nil)
    end
    fixedByRules = false
end

local function updateTrackTemp()
    if clock < nextTrackCheck then
        return
    end
    nextTrackCheck = clock + 1
    local road = rawget(_G, "roadTemperature")
    local bji = Platform.get("BJI")
    if not road or not road.get then
        M.trackTemp = nil
        return
    end
    if not (bji and bji.CLIENT_READY) then
        releaseFixed(road)
        M.trackTemp = nil
        return
    end
    local rules = M.getRules(currentRaceID())
    if rules.trackTempFixed and tonumber(rules.trackTemp) then
        road.setFixed(tonumber(rules.trackTemp), "race rules")
        fixedByRules = true
    else
        releaseFixed(road)
    end
    M.trackTemp = road.get()
end

---------------------------------------------------------------- tyre wear rule
-- Kagoni Tyre Simulation keeps its wear switch in the vehicle VM
-- (extensions.luukstyrethermalsandwear.setTyreWearEnabled). Its setter also
-- saves the driver's preference, so only switch when it differs.

local TYRE_WEAR_CHECK_S = 3
local nextTyreWearCheck = 0

local function enforceTyreWear()
    if clock < nextTyreWearCheck then
        return
    end
    nextTyreWearCheck = clock + TYRE_WEAR_CHECK_S
    local bji = Platform.get("BJI")
    local vehicles = Platform.get("BJI_Veh")
    if not (bji and bji.CLIENT_READY and vehicles and vehicles.getCurrentVehicleOwn) then
        return
    end
    local mode = M.getRules(currentRaceID()).tyreWear
    if mode ~= "on" and mode ~= "off" then
        return
    end
    local veh = vehicles.getCurrentVehicleOwn()
    if not veh then
        return
    end
    local want = mode == "on" and "true" or "false"
    veh:queueLuaCommand(string.format(
        "local e = extensions.luukstyrethermalsandwear " ..
        "if e and e.getTyreWearEnabled and e.setTyreWearEnabled and e.getTyreWearEnabled() ~= %s then " ..
        "e.setTyreWearEnabled(%s) end", want, want))
end

---------------------------------------------------------------- slick compound (KTS)
-- Grip and PI come from the fitted Race Prep slick (Automation's Soft /
-- Medium / Hard Race data); Kagoni Tyre Simulation's slick preset (wear,
-- temperature window) is kept on the same compound. KTS's own compound
-- buttons would otherwise give Soft wear/heat on Hard-rated tyres.
local SLICK_CHECK_S = 2
local nextSlickCheck = 0

local function syncSlickCompound()
    if clock < nextSlickCheck then
        return
    end
    nextSlickCheck = clock + SLICK_CHECK_S
    local bji = Platform.get("BJI")
    local vehicles = Platform.get("BJI_Veh")
    if not (bji and bji.CLIENT_READY and vehicles and vehicles.getCurrentVehicleOwn) then
        return
    end
    local veh = vehicles.getCurrentVehicleOwn()
    if not veh then
        return
    end
    local ok, upgrades = pcall(require, "ge/extensions/raceprep/upgrades")
    -- the real tyre type first (Automation cars only; KTS sees them as Standard),
    -- set only when it differs, so KTS's thermal state is not reset every check
    local profile = ok and upgrades.ktsProfile and upgrades.ktsProfile(veh:getID())
    if profile then
        veh:queueLuaCommand(string.format(
            "local e = extensions.luukstyrethermalsandwear " ..
            "if e and e.getTyreProfilePreset and e.setTyreProfilePreset and e.getTyreProfilePreset() ~= %q then " ..
            "e.setTyreProfilePreset(%q) end", profile, profile))
    end
    local preset = ok and upgrades.slickPreset and upgrades.slickPreset(veh:getID())
    if not preset then
        return
    end
    veh:queueLuaCommand(string.format(
        "local e = extensions.luukstyrethermalsandwear " ..
        "if e and e.getSlickCompoundPreset and e.setSlickCompoundPreset and e.getSlickCompoundPreset() ~= %q then " ..
        "e.setSlickCompoundPreset(%q) end", preset, preset))
end

---------------------------------------------------------------- driving aids rule
-- ABS through wheels.setABSBehavior; traction and stability control are the
-- tractionControl / yawControl supervisors (Automation's CMU and BeamNG's own
-- drivingDynamics). Drive-mode changes can switch them back, so the rule is
-- re-applied every few seconds. "on" only works on cars that have the system.
-- The vehicle reports what it has, for the Race tab.

local AIDS_CHECK_S = 2
local nextAidsCheck = 0
-- game vehicle id -> {abs, hasTC, tc, hasESC, esc}
M.aids = {}

local function aidValue(mode)
    if mode == "on" then return "true" elseif mode == "off" then return "false" end
    return "nil"
end

local function enforceAids()
    if clock < nextAidsCheck then
        return
    end
    nextAidsCheck = clock + AIDS_CHECK_S
    local bji = Platform.get("BJI")
    local vehicles = Platform.get("BJI_Veh")
    if not (bji and bji.CLIENT_READY and vehicles and vehicles.getCurrentVehicleOwn) then
        return
    end
    local veh = vehicles.getCurrentVehicleOwn()
    if not veh then
        return
    end
    local rules = M.getRules(currentRaceID())
    veh:queueLuaCommand(string.format([[
local abs, tc, esc = %s, %s, %s
local function hasABS()
  local v = electrics.values.hasABS
  return v == true or (tonumber(v) or 0) > 0
end
if abs == false and hasABS() then wheels.setABSBehavior("off")
elseif abs == true and not hasABS() then wheels.setABSBehavior("realistic") end
local r = { abs = hasABS() }
for key, name in pairs({ tc = "tractionControl", esc = "yawControl" }) do
  local c = controller.getController(name)
  local want = esc
  if key == "tc" then want = tc end
  if c and c.setParameters and c.getConfig then
    if want ~= nil then c.setParameters({ isEnabled = want }) end
    r["has" .. key] = true
    r[key] = c.getConfig().isEnabled == true
  end
end
obj:queueGameEngineLua("if bjiRacePrep then bjiRacePrep.onAidsReport(" .. obj:getId() .. ", " .. serialize(r) .. ") end")
]], aidValue(rules.abs), aidValue(rules.tc), aidValue(rules.esc)))
end

---------------------------------------------------------------- rolling start
-- After BeamJoy's countdown the grid drives at the pace speed (the vehicle
-- extension raceprepLimiter caps the driver's throttle). Green when the first
-- car reaches checkpoint 1: every game sees the same leaderboard update.
-- Getting ahead of the car that started in front before green is warned.
-- Lap 1 includes the formation run for everyone.

M.rolling = { phase = nil } -- phase: nil | "formation" | "green"
local rollingRun = nil
local nextLimiterSend = 0
local nextJumpCheck = 0

local function flash(key, text, seconds)
    local msg = Platform.get("BJI_Message")
    if msg and msg.flash then
        pcall(msg.flash, key, text, seconds or 3, false)
    end
end

local function setLimiter(veh, kmh)
    if not veh then return end
    if kmh then
        veh:queueLuaCommand(string.format(
            'extensions.load("raceprepLimiter") if raceprepLimiter then raceprepLimiter.setPace(%d) end', kmh))
    else
        veh:queueLuaCommand('if raceprepLimiter then raceprepLimiter.release() end')
    end
end

local function anyPassedFirstCheckpoint(race)
    for _, lb in ipairs(race.race.leaderboard or {}) do
        if (lb.lap or 1) > 1 or (lb.wp or 0) >= 1 then
            return true
        end
    end
    return false
end

local function updateRollingStart()
    local BJI_Context=Platform.get("BJI_Context")
    local scenario = Platform.get("BJI_Scenario")
    local race = scenario and scenario.TYPES and scenario.get(scenario.TYPES.RACE_MULTI)
    local vehicles = Platform.get("BJI_Veh")
    local active = race and race.state and race.STATES and race.state == race.STATES.RACE and race.race and
        race.race.startTime and race.isParticipant and race.isParticipant() and
        not (race.isFinished and race.isFinished())
    local key = active and (tostring(race.raceID) .. ":" .. tostring(race.race.startTime)) or nil
    local veh = vehicles and vehicles.getCurrentVehicleOwn and vehicles.getCurrentVehicleOwn()
    if not active then
        if M.rolling.phase == "formation" then setLimiter(veh, nil) end
        M.rolling = { phase = nil }
        rollingRun = nil
        return
    end
    if rollingRun ~= key then
        rollingRun = key
        local rules = M.getRules(race.raceID)
        M.rolling = { phase = rules.startType == "rolling" and "pending" or nil,
            pace = math.floor(tonumber(rules.paceSpeed) or 80) }
    end
    local r = M.rolling
    if not r.phase or r.phase == "green" then
        return
    end
    local now = GetCurrentTimeMillis and GetCurrentTimeMillis() or 0
    local started = race.race.startTime and now >= race.race.startTime
    if r.phase == "pending" then
        if not started then return end
        r.phase = "formation"
        nextLimiterSend = 0
        flash("RacePrepRolling", string.format("Rolling start: pace %d km/h, hold your position until green", r.pace), 5)
    end
    local nativeRolling=Platform.isBJR() and require('ge/extensions/raceprep/bjr/rollingStart')
    local nativeSession=Platform.isBJR() and beamjoy_raceRunner and beamjoy_raceRunner.session
    if (nativeRolling and nativeRolling.released(nativeSession)) or (not nativeRolling and anyPassedFirstCheckpoint(race)) then
        r.phase = "green"
        r.warning=nil
        setLimiter(veh, nil)
        flash("RacePrepRolling", "GREEN! GREEN! GREEN!", 3)
        return
    end
    -- keep the limiter on (a reset reloads the vehicle extension)
    if clock >= nextLimiterSend then
        nextLimiterSend = clock + 2
        setLimiter(veh, r.pace)
    end
    -- overtaking before green: compare with the car that started ahead
    if clock >= nextJumpCheck then
        nextJumpCheck = clock + 0.5
        local okT, timing = pcall(require, "ge/extensions/raceprep/timing")
        local snap = not Platform.isBJR() and okT and timing and timing.get({ now = now, players = (Platform.get("BJI_Context") or {}).Players })
        local grid = race.grid and race.grid.participants or {}
        local selfID = BJI_Context and BJI_Context.User and BJI_Context.User.playerID
        local myIndex
        for i, pid in ipairs(grid) do if pid == selfID then myIndex = i end end
        if nativeRolling then
            local nativeRace=require('ge/extensions/raceprep/frontend').host().race()
            local pass=nativeRolling.check(nativeSession,nativeRace,selfID,require('ge/extensions/raceprep/bjr/driving').positions())
            r.warning=pass and ('Do not pass before green — drop back behind '..pass.name..string.format(' (%.1f m ahead)',pass.metres)) or nil
            if r.warning then flash('RacePrepRollingJump',r.warning,2) end
        end
        if snap and myIndex and myIndex > 1 then
            local progress = {}
            for _, e in ipairs(snap.entries or {}) do progress[e.playerID] = e.progress end
            local mine, ahead = progress[selfID], progress[grid[myIndex - 1]]
            if mine and ahead and mine > ahead + 2 then
                flash("RacePrepRollingJump", "Do not pass before green - drop back behind " ..
                    tostring(((BJI_Context.Players or {})[grid[myIndex - 1]] or {}).playerName or "the car ahead"), 2)
            end
        end
    end
end

-- called from the vehicle VM (raceprepLimits): a track-limits cut
M.onRaceTelemetry = function(id,data) require("ge/extensions/raceprep/director").onTelemetry(id,data) end

M.onCut = function(gameVehID)
 local rivals=package.loaded['ge/extensions/raceprep/bjr/rivalsSession'];if rivals then rivals.cut(gameVehID) end
    local ok, session = pcall(require, "ge/extensions/raceprep/session")
    if ok then session.onCut(gameVehID) end
end

-- called from the vehicle VM
M.onAidsReport = function(gameVehID, report)
    M.aids[gameVehID] = type(report) == "table" and report or nil
end

---------------------------------------------------------------- Race Settings rules + selector badges
-- The race rules are edited where the race is set up: a "Race Prep rules"
-- section is added under BeamJoy's own Race Settings (multiplayer races,
-- SetConfig holders). BeamJoy reads window sizes every frame, so the window
-- grows while the section is open. BeamJoy itself is not modified.

local rulesSectionOpen = false
local nextBadgeInject = 0

local function hookRaceSettings()
    local w = rawget(_G, "BJI_Win_RaceSettings")
    local prep = rawget(_G, "BJI_Win_RacePrep")
    if not w or not prep or not prep.drawRulesEditor or w.__raceprepBody == w.body then
        return
    end
    local original = w.__raceprepOriginalBody or w.body
    w.__raceprepOriginalBody = original
    local baseMin, baseMax = w.minSize, w.maxSize
    local loggedFor = nil
    w.body = function(ctxt)
        original(ctxt)
        local multi = w.settings and w.settings.multi
        local canEdit = prep.canEditRules and prep.canEditRules()
        if loggedFor ~= w.settings then
            loggedFor = w.settings
            log("I", string.format("Race Settings opened: race %s, multiplayer=%s, can edit rules=%s",
                tostring(w.settings and w.settings.raceID), tostring(multi), tostring(canEdit)))
        end
        if not multi or not canEdit then
            w.minSize, w.maxSize = baseMin, baseMax
            return
        end
        Separator()
        if Button("raceprep-racesettings-rules", rulesSectionOpen and "Hide Race Prep rules" or
                "Race Prep rules: classes, PI, parts, nitrous, aids, start...", {
                    btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO, width = -1 }) then
            rulesSectionOpen = not rulesSectionOpen
        end
        if rulesSectionOpen then
            w.minSize, w.maxSize = ImVec2(560, 640), ImVec2(1800, 2000)
            prep.drawRulesEditor(w.settings.raceID, w.settings.raceName)
        else
            w.minSize, w.maxSize = baseMin, ImVec2(baseMax and baseMax.x or 700, 300)
        end
    end
    w.__raceprepBody = w.body
    log("I", "Race Prep rules section added to BeamJoy's Race Settings window")
end

-- BeamJoy's vehicle selector asks the race for its car list
-- (scenario getModelList). With class or PI limits, show only the configs the
-- race rules allow (same check as Ready). Unrated cars stay listed: they are
-- rated when spawned and Ready still checks them.
local function filteredModelList(race, original, ...)
    local models = original(...)
    if type(models) ~= "table" or next(models) == nil then
        return models
    end
    local ok, ratingMod = pcall(require, "ge/extensions/raceprep/rating")
    local ratings = rawget(_G, "raceprepRatings")
    local rules = M.getRules(race.raceID)
    if not ok or not ratings or not ratings.getConfig or not ratingMod.violation(rules, nil) then
        return models -- no class / PI limits
    end
    local out = {}
    for modelKey, model in pairs(models) do
        if type(model) == "table" and type(model.configs) == "table" then
            local configs, count = {}, 0
            for configKey, config in pairs(model.configs) do
                local entry = ratings.getConfig(modelKey, (type(config) == "table" and config.key) or configKey)
                if not entry or not ratingMod.violation(rules, entry) then
                    configs[configKey] = config
                    count = count + 1
                end
            end
            if count > 0 then
                local copy = {}
                for k, v in pairs(model) do copy[k] = v end
                copy.configs = configs
                out[modelKey] = copy
            end
        else
            out[modelKey] = model
        end
    end
    return out
end

local function hookRaceModelList()
    local scenario = Platform.get("BJI_Scenario")
    local race = scenario and scenario.TYPES and scenario.get and scenario.get(scenario.TYPES.RACE_MULTI)
    if not race or type(race.getModelList) ~= "function" or race.getModelList == race.__raceprepModelList then
        return
    end
    local original = race.__raceprepOriginalModelList or race.getModelList
    race.__raceprepOriginalModelList = original
    race.getModelList = function(...)
        local ok, result = pcall(filteredModelList, race, original, ...)
        if ok then
            return result
        end
        log("E", "Vehicle list filter: " .. tostring(result))
        return original(...)
    end
    race.__raceprepModelList = race.getModelList
end

-- "Race Prep" menu in BeamJoy's top menu bar (free roam too): track settings
-- (admins), race control / driver statistics, last race results, session.
-- BeamJoy's main window calls menu.draw each frame, so the menu module's draw
-- is wrapped; BeamJoy itself is not modified.
local function raceprepMenuItems()
    local items = {}
    local prep = rawget(_G, "BJI_Win_RacePrep")
    local track = rawget(_G, "BJI_Win_RaceTrack")
    local okD, director = pcall(require, "ge/extensions/raceprep/director")
    local okR, results = pcall(require, "ge/extensions/raceprep/results")
    local okS, session = pcall(require, "ge/extensions/raceprep/session")
    local up = rawget(_G, "BJI_Win_RaceUpgrades")
    if up then
        table.insert(items, { type = "item", label = "Upgrades & tuning (my car)", active = up.show == true,
            onClick = function() up.show = not up.show end })
    end
    if track and prep and prep.canEditRules and prep.canEditRules() then
        table.insert(items, { type = "item", label = "Track settings (rubber, wind)", active = track.show == true,
            onClick = function() track.show = not track.show end })
    end
    if okD then
        table.insert(items, { type = "item", label = "Race control / driver stats", active = director.show == true,
            onClick = function() director.show = not director.show end })
    end
    if okR and results.last then
        table.insert(items, { type = "item", label = "Last race results", active = results.visible == true,
            onClick = function() results.visible = not results.visible end })
    end
    local w = rawget(_G, "BJI_Win_RaceSession")
    if okS and w and w.reopen and session.data and (session.data.state == "running" or session.data.state == "overtime") then
        table.insert(items, { type = "item", label = "Practice / qualifying session", onClick = function() w.reopen() end })
    end
    return items
end

-- The main window copies Menu.draw into its own "menu" field at load, so the
-- registered window object is wrapped (wrapping the Menu module does nothing).
local function hookMainMenu()
    local windows = Platform.get("BJI_Windows")
    local main
    for _, w in pairs(windows and windows.windows or {}) do
        if w.name == "Main" then
            main = w
            break
        end
    end
    if not main or type(main.menu) ~= "function" or main.menu == main.__raceprepMenu then
        return
    end
    local original = main.__raceprepOriginalMenu or main.menu
    main.__raceprepOriginalMenu = original
    main.menu = function(ctxt, ...)
        original(ctxt, ...)
        local ok, items = pcall(raceprepMenuItems)
        if ok and #items > 0 and type(rawget(_G, "RenderMenuDropdown")) == "function" then
            RenderMenuDropdown("Race Prep", items)
        end
    end
    main.__raceprepMenu = main.menu
    log("I", "Race Prep menu added to BeamJoy's menu bar")
end

local function injectBadges()
    if clock < nextBadgeInject then
        return
    end
    nextBadgeInject = clock + 10
    local ok, style = pcall(require, "ge/extensions/raceprep/classStyle")
    if ok and style then
        style.injectSelectorBadges()
    end
end

M.hasRoadTemperature = function()
    return rawget(_G, "roadTemperature") ~= nil
end

---------------------------------------------------------------- hooks

-- Slow-frame report: when one onUpdate takes more than SLOW_FRAME_MS, the
-- console gets which steps took the time (at most every 10 s). Added for the
-- "spike every 15 s" report (2026-10-16); costs a dozen clock reads a frame.
M.SLOW_FRAME_MS = 4
local frameLast, frameSteps, frameN, slowLogAt = 0, {}, 0, -1e9
local function frameMS()
    return Engine and Engine.Platform and Engine.Platform.getSystemTimeMS and Engine.Platform.getSystemTimeMS()
        or os.clock() * 1000
end
local function mark(name)
    local t = frameMS()
    frameSteps[frameN + 1], frameSteps[frameN + 2] = name, t - frameLast
    frameN, frameLast = frameN + 2, t
end
M.slowFrame = nil -- last report, for tests

local update
local Prof = require("ge/extensions/raceprep/prof")
Prof.hook()
-- The every-extension timing (2026-10-17, "spike every 15 s") is off: the
-- spike was the 137 estimate lookup, and timing every extension hook costs
-- every frame. Set true to diagnose again; BJR:ME's own spike line stays on.
local PROFILE_EXTENSIONS = false
local profilingExtensions = not PROFILE_EXTENSIONS
M.onUpdate = function(dtReal)
    Prof.tick(dtReal, function(_, _, msg) log("W", msg) end)
    Prof.hook()
    if not profilingExtensions then profilingExtensions = Prof.profileExtensions(true) end
    local started = frameMS()
    frameLast, frameN = started, 0
    update(dtReal)
    local total = frameMS() - started
    Prof.add("bjiRacePrep", total)
    if total > M.SLOW_FRAME_MS and clock - slowLogAt >= 10 then
        slowLogAt = clock
        local parts = {}
        for i = 1, frameN, 2 do
            if frameSteps[i + 1] >= 0.5 then parts[#parts + 1] = string.format("%s %.1f", frameSteps[i], frameSteps[i + 1]) end
        end
        M.slowFrame = string.format("Slow frame %.1f ms: %s", total, #parts > 0 and table.concat(parts, ", ") or "spread over all steps")
        log("W", M.slowFrame)
    end
end

update = function(dtReal)
    if not rawget(_G,'raceprepBJR') and rawget(_G,'beamjoy_main') then extensions.load('raceprepBJR') end
    if Platform.isBJR() and not handlersRegistered then
        handlersRegistered=registerHandlers() or false
    end
    clock = clock + (dtReal or 0)
    for gameVehID, at in pairs(pendingReapply) do
        if clock >= at then
            pendingReapply[gameVehID] = nil
            M.applyDiff(gameVehID, M.diffSettings[gameVehID])
        end
    end
    requestRulesWhenConnected()
    mark('rules')
    updateTrackTemp()
    mark('trackTemp')
    enforceTyreWear()
    mark('tyreWear')
    local sok, serr = pcall(syncSlickCompound)
    if not sok then log("E", "Slick compound: " .. tostring(serr)) end
    mark('slicks')
    enforceAids()
    mark('aids')
    pcall(injectBadges)
    mark('badges')
    if beamJoyReady() then
        local hok, herr = pcall(hookRaceSettings)
        if not hok then log("E", "Race Settings hook: " .. tostring(herr)) end
        local nok, nerr = pcall(hookMainMenu)
        if not nok then log("E", "Menu hook: " .. tostring(nerr)) end
        local mok, merr = pcall(hookRaceModelList)
        if not mok then log("E", "Vehicle list hook: " .. tostring(merr)) end
    end
    mark('hooks')
    local rsok, rserr = pcall(updateRollingStart)
    if not rsok then
        log("E", "Rolling start: " .. tostring(rserr))
    end
    mark('rollingStart')
    local sok, session = pcall(require, "ge/extensions/raceprep/session")
    if sok and session then
        session.update(clock)
    else
        log("E", "Sessions: " .. tostring(session))
    end
    mark('session')
    local rok, results = pcall(require, "ge/extensions/raceprep/results")
    if rok and results and not Platform.isBJR() then
        local uok, err = pcall(results.update, clock)
        if not uok then
            log("E", "Race results: " .. tostring(err))
        end
    end

    -- headlights of Automation cars: aimed, brighter, longer (raceprep/headlights)
    local hok, headlights = pcall(require, "ge/extensions/raceprep/headlights")
    if hok and not headlights.failed then
        local ok, err = pcall(headlights.update, clock)
        if not ok then headlights.failed = true; log("E", "Headlights off for this session: " .. tostring(err)) end
    end
    mark('headlights')
    local dok, director = pcall(require, "ge/extensions/raceprep/director")
    if dok then local ok,err=pcall(director.update,clock);if not ok then log("E","Race control: "..tostring(err)) end end
    mark('raceControl')
    if not beamJoyReady() or handledWindows == BJI_Windows.windows then
        return
    end
    local ok, err = pcall(register)
    if not ok then
        log("E", "RacePrep registration failed: " .. tostring(err))
    end
    -- one attempt per BeamJoy instance; failures are logged, not retried
    -- every frame
    do
        handledWindows = BJI_Windows.windows
        -- new BeamJoy instance (first load or reconnect): fetch the rules again
        M.rules = nil
        nextRulesRequest = 0
        local hok, registered = pcall(registerHandlers)
        handlersRegistered = hok and registered or false
        if not handlersRegistered then
            log("W", "BeamMP events unavailable; RacePrep uses built-in rules")
        end
    end
end

M.onExtensionUnloaded = function()
    local old=package.loaded['ge/extensions/raceprep/raceRubber']
    if old and old.restore then old.restore() end
    require('ge/extensions/raceprep/rubberLine').restore()
    require('ge/extensions/raceprep/rubberLine').clear()
    require('ge/extensions/raceprep/rubberSurface').restore()
    require("ge/extensions/raceprep/raceEnvironment").restore()
    require("ge/extensions/raceprep/weather").restore()
    releaseFixed(rawget(_G, "roadTemperature"))
end

M.onPreRender=function()
    local t=Prof.now()
    local line=package.loaded['ge/extensions/raceprep/rubberLine']
    if line then line.draw() end
    local marbles=package.loaded['ge/extensions/raceprep/rubberMarbles']
    if marbles then marbles.draw() end
    Prof.add("draw rubber+marbles", Prof.now()-t)
end

M.onExtensionLoaded = function()
    if Platform.isBJR() then return end
    log("I", "BeamJoy RacePrep add-on loaded")
    if not rawget(_G, "raceprepRatings") then extensions.load("raceprepRatings") end
end

return M
