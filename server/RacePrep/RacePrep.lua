-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- RacePrep server plugin: stores the race-preparation rules (what drivers may
-- change on the grid) and sends them to the BJI_RacePrep client add-on.
--
-- Rules live in rules.json next to this file:
--   { "default": { ...rules for every race... },
--     "races": { "<BeamJoy race id>": { ...override for that race... } } }
-- They can be edited in-game (RacePrep window > Rules, for players whose
-- BeamJoy group has the SetConfig permission) or in the file, followed by a
-- server restart.
--
-- Limits are applied by each driver's client: car physics run on the
-- driver's own machine, so the server cannot check them itself.
--
-- It also keeps the race history (history/ next to this file) from the
-- results the drivers' games send when a race finishes.

local pluginPath = debug.getinfo(1).source:gsub("^@", ""):gsub("\\", "/")
pluginPath = pluginPath:sub(1, (pluginPath:find("RacePrep.lua", 1, true)) - 2)
local raceControl
local Persistence=dofile(pluginPath..'/Persistence.lua')
local Rivals=dofile(pluginPath..'/Rivals.lua')
local ClassBuild=dofile(pluginPath..'/ClassBuild.lua')
local AnchorSelection=dofile(pluginPath..'/AnchorSelection.lua')
local ChallengeCatalogue=dofile(pluginPath..'/ChallengeCatalogue.lua')
local rivalsDriver
local features={rating=dofile(pluginPath..'/DriverRating.lua'),awards=dofile(pluginPath..'/RaceAwards.lua').new()}
local rivalContexts={}
local bjrApi
local host=dofile(pluginPath .. "/BJRHost.lua")
-- what this BeamJoy-Revived supports (BJRApi.capabilities); false until its API answers
local function bjrCan(feature) return host.enabled and bjrApi~=nil and bjrApi.caps~=nil and bjrApi.caps[feature]==true end
-- a BeamJoy-Revived without race.penalize: BJR:ME adds penalties to its own results (as 2.16 did)
local function localPenalties() return host.enabled and bjrApi~=nil and bjrApi.caps~=nil and bjrApi.caps.penalties==false end

local trustedNativeResult=false
local rulesFile = pluginPath .. "/rules.json"
local beamJoyDb = pluginPath:gsub("RacePrep$", "BeamJoyData/db")
local RatingStore = dofile(pluginPath .. "/RatingStore.lua")
local RatingIdentity = dofile(pluginPath .. "/RatingIdentity.lua")
local ratingsFile = pluginPath .. "/ratings.json"
local ratings
local ratingVehicles = {}
local ratingReports = {}
local ratingPresentations = {}
local function displayRating(key)
    return ratings and RatingStore.present(ratings.entries[key],ratingPresentations[key],ratings.constants)
end
local function refreshCars(pid)
    if bjrApi and bjrApi.refreshCars then bjrApi.refreshCars(pid) end
end

local DEFAULT_RULES = {
    tuning = true,
    fuel = true,
    aero = true,
    diff = true,
    diffModes = { open = true, lsd = true, locked = true },
    slickCompounds = { supersoft = true, soft = true, medium = true, hard = true },
    centreSplit = true,
    centreSplitMin = 0.2,
    centreSplitMax = 0.8,
    maxPreload = 500,
    maxLock = 100,
    trackTempFixed = false,
    trackTemp = 30,
    tyreWear = "driver",
    startType = "standing",
    rubberBuildUp = false, rubberInitial = 20, rubberBuildKm = 50, rubberDryBonus = 3, rubberWetPenalty = 5,
    windEnabled = false, windSpeedKmh = 15, windDirection = 0, windGustKmh = 5, windGustPeriod = 12,
    safetyRating = false,
    minSkill = 0, minSafety = "", minLicence = "", seriesName = "", specModel = "", specConfig = "",
    yellowFlags = false,
    startLights = false, falseStartPenaltySeconds = 0, falseStartTolerance = .75,
    paceSpeed = 80,
    allowedClasses = { E=true, D=true, C=true, B=true, A=true, S=true, R=true, P=true, X=true },
    piMin = false,
    piMax = false,
    targetClass = "",
    parts = { engine = "any", drivetrain = "any", suspension = "any", tyres = "any", body = "any" },
    -- upgrade caps (client raceprep/upgradeRules.lua): most permissive by default
    upgrades = { engine = "race", induction = "allow", engineConversion = true, drivetrainConversion = "any",
        compound = "slick", width = 40, weight = "race", brakes = "race", radiators = true },
    nitrous = true,
    abs = "driver",
    tc = "driver",
    esc = "driver",
    -- sessions before the race (minutes, 0 = none) and the grid order
    practiceMinutes = 0,
    qualifyingMinutes = 0,
    gridOrder = "join", -- join | qualifying | reverse | handicap
    gridReverseTop = 6,
    -- track limits: all wheels off the track surface
    trackLimits = "invalid", -- off | invalid (lap does not count) | penalty
    cutPenaltyAfter = 3,     -- penalty mode: cuts allowed before penalties
    cutPenaltySeconds = 5,   -- added per cut after that
}

local PART_GROUPS = { "engine", "drivetrain", "suspension", "tyres", "body" }

local function choice(value, allowed, fallback)
    for _, a in ipairs(allowed) do
        if value == a then
            return value
        end
    end
    return fallback
end

local rules = { default = {}, races = {} }

-- Console output in BeamJoy's style: coloured tag, coloured message
local ESC = string.char(27)
local function colour(code) return ESC .. "[" .. code .. "m" end
local function log(msg)
    print(colour("38;5;208") .. "[BJR:ME]" .. colour(0) .. " " .. colour(96) .. tostring(msg) .. colour(0))
end
local function logWarn(msg)
    print(colour(33) .. "[BJR:ME]" .. colour(0) .. " " .. colour(93) .. tostring(msg) .. colour(0))
end

local function readJson(path)
    if not FS.Exists(path) then
        if FS.Exists(path..'.bak') then path=path..'.bak' else return nil end
    end
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(Util.JsonDecode, content)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local hostConfig=readJson(pluginPath .. "/host.json")
host.enabled=type(hostConfig)=="table" and hostConfig.host=="beamjoy-revived"
local VERSION = host.enabled and tostring(hostConfig.version or "dev") or "dev"
local BUILD = VERSION:match("%.(%d+)$") or "dev"
local RELEASE = VERSION:match("^(%d+%.%d+%.%d+)") or VERSION -- v2.10.0 of v2.10.0.97
-- BeamJoy's [INFO] style (light blue tag, cyan text); BeamMP adds "[time] [LUA]"
local function logInfo(msg)
    print(colour(94) .. "[INFO]" .. colour(0) .. " " .. colour(36) .. tostring(msg) .. colour(0))
end
local function drawArt()
    -- checkered flag, "BeamJoy-Revived:" with "Motorsport Expansion" tucked under
    -- it (figlet "Slant", like BeamJoy's banner; lines overlap where letters
    -- allow), checkered flag
    print(colour(97) .. "\n" .. [[
██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██
  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██
    ____                           __                  ____            _                __
   / __ )___  ____ _____ ___      / /___  __  __      / __ \___ _   __(_)   _____  ____/ /
  / __  / _ \/ __ `/ __ `__ \__  / / __ \/ / / /_____/ /_/ / _ \ | / / / | / / _ \/ __  (_)
 / /_/ /  __/ /_/ / / / / / / /_/ / /_/ / /_/ /_____/ _, _/  __/ |/ / /| |/ /  __/ /_/ /
/_____/\___/\__,_/_/ /_/ /_/\____/\____/\__, /     /_/ |_|\___/|___/_/ |___/\___/\__,_(_)
          __  ___      __              /____/               __     ______                            _
         /  |/  /___  / /_____  ______________  ____  _____/ /_   / ____/  ______  ____ _____  _____(_)___  ____
        / /|_/ / __ \/ __/ __ \/ ___/ ___/ __ \/ __ \/ ___/ __/  / __/ | |/_/ __ \/ __ `/ __ \/ ___/ / __ \/ __ \
       / /  / / /_/ / /_/ /_/ / /  (__  ) /_/ / /_/ / /  / /_   / /____>  </ /_/ / /_/ / / / (__  ) / /_/ / / / /
      /_/  /_/\____/\__/\____/_/  /____/ .___/\____/_/   \__/  /_____/_/|_/ .___/\__,_/_/ /_/____/_/\____/_/ /_/
                                      /_/                                /_/
██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██
  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██  ██
]] .. colour(0))
end


local function bool(value, fallback)
    if type(value) == "boolean" then
        return value
    end
    return fallback
end

local function number(value, fallback, min, max)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(min, math.min(max, value))
end

-- keeps only known keys with sane values
local function sanitize(input, base)
    input = type(input) == "table" and input or {}
    base = base or DEFAULT_RULES
    local modes = type(input.diffModes) == "table" and input.diffModes or {}
    local out = {
        tuning = bool(input.tuning, base.tuning),
        fuel = bool(input.fuel, base.fuel),
        aero = bool(input.aero, base.aero),
        diff = bool(input.diff, base.diff),
        diffModes = {
            open = bool(modes.open, base.diffModes.open),
            lsd = bool(modes.lsd, base.diffModes.lsd),
            locked = bool(modes.locked, base.diffModes.locked),
        },
        centreSplit = bool(input.centreSplit, base.centreSplit),
        centreSplitMin = number(input.centreSplitMin, base.centreSplitMin, 0, 1),
        centreSplitMax = number(input.centreSplitMax, base.centreSplitMax, 0, 1),
        maxPreload = number(input.maxPreload, base.maxPreload, 0, 5000),
        maxLock = number(input.maxLock, base.maxLock, 0, 100),
        trackTempFixed = bool(input.trackTempFixed, base.trackTempFixed),
        trackTemp = number(input.trackTemp, base.trackTemp, 0, 70),
        tyreWear = (input.tyreWear == "on" or input.tyreWear == "off" or input.tyreWear == "driver")
            and input.tyreWear or base.tyreWear,
        allowedClasses = RatingStore.classes(input.allowedClasses, base.allowedClasses),
        slickCompounds = {},
        piMin = RatingStore.bound(input.piMin, base.piMin),
        piMax = RatingStore.bound(input.piMax, base.piMax),
        targetClass = choice(input.targetClass, {"", "D", "C", "B", "A", "S", "R"}, base.targetClass or ""),
        parts = {},
        nitrous = bool(input.nitrous, base.nitrous),
        startType = choice(input.startType, { "standing", "rolling" }, base.startType),
        rubberBuildUp = bool(input.rubberBuildUp, base.rubberBuildUp),
        rubberInitial = number(input.rubberInitial, base.rubberInitial, 0, 100),
        rubberBuildKm = number(input.rubberBuildKm, base.rubberBuildKm, 1, 500),
        rubberDryBonus = number(input.rubberDryBonus, base.rubberDryBonus, 0, 10),
        rubberWetPenalty = number(input.rubberWetPenalty, base.rubberWetPenalty, 0, 20),
        windEnabled = bool(input.windEnabled, base.windEnabled),
        windSpeedKmh = number(input.windSpeedKmh, base.windSpeedKmh, 0, 120),
        windDirection = number(input.windDirection, base.windDirection, 0, 360),
        windGustKmh = number(input.windGustKmh, base.windGustKmh, 0, 60),
        windGustPeriod = number(input.windGustPeriod, base.windGustPeriod, 2, 120),
        safetyRating = bool(input.safetyRating, base.safetyRating),
        minSkill = math.floor(number(input.minSkill, base.minSkill or 0, 0, 5000)),
        minLicence = choice(input.minLicence, {"", "D", "C", "B", "A", "Pro"}, base.minLicence or ""),
        minSafety = choice(input.minSafety, { "", "F", "E", "D", "C", "B", "A", "S" }, base.minSafety or ""),
        seriesName = type(input.seriesName)=='string' and input.seriesName:gsub('%c',' '):sub(1,80) or base.seriesName or '',
        specModel = type(input.specModel)=='string' and (input.specModel=='' or input.specModel:match('^[%w_-]+$')) and input.specModel:sub(1,128) or base.specModel or '',
        specConfig = type(input.specConfig)=='string' and (input.specConfig=='' or input.specConfig:match('^[%w_ %-]+$')) and input.specConfig:sub(1,128) or base.specConfig or '',
        yellowFlags = bool(input.yellowFlags, base.yellowFlags),
        startLights = bool(input.startLights, base.startLights),
        falseStartPenaltySeconds = number(input.falseStartPenaltySeconds, base.falseStartPenaltySeconds, 0, 60),
        falseStartTolerance = number(input.falseStartTolerance, base.falseStartTolerance, .25, 3),
        paceSpeed = number(input.paceSpeed, base.paceSpeed, 40, 150),
        abs = choice(input.abs, { "driver", "on", "off" }, base.abs),
        tc = choice(input.tc, { "driver", "on", "off" }, base.tc),
        esc = choice(input.esc, { "driver", "on", "off" }, base.esc),
        practiceMinutes = math.floor(number(input.practiceMinutes, base.practiceMinutes or 0, 0, 120)),
        qualifyingMinutes = math.floor(number(input.qualifyingMinutes, base.qualifyingMinutes or 0, 0, 120)),
        gridOrder = choice(input.gridOrder, { "join", "qualifying", "reverse", "handicap", "skill", "safety" }, base.gridOrder or "join"),
        gridReverseTop = math.floor(number(input.gridReverseTop, base.gridReverseTop or 6, 2, 30)),
        trackLimits = choice(input.trackLimits, { "off", "invalid", "penalty" }, base.trackLimits or "invalid"),
        cutPenaltyAfter = math.floor(number(input.cutPenaltyAfter, base.cutPenaltyAfter or 3, 0, 50)),
        cutPenaltySeconds = number(input.cutPenaltySeconds, base.cutPenaltySeconds or 5, 1, 60),
    }
    local slicks = type(input.slickCompounds) == "table" and input.slickCompounds or {}
    local baseSlicks = type(base.slickCompounds) == "table" and base.slickCompounds or {}
    for _, id in ipairs({ "supersoft", "soft", "medium", "hard" }) do
        out.slickCompounds[id] = bool(slicks[id], baseSlicks[id] ~= false)
    end
    local parts = type(input.parts) == "table" and input.parts or {}
    local baseParts = type(base.parts) == "table" and base.parts or DEFAULT_RULES.parts
    for _, group in ipairs(PART_GROUPS) do
        out.parts[group] = choice(parts[group], { "any", "stock" }, baseParts[group] or "any")
    end
    local up = type(input.upgrades) == "table" and input.upgrades or {}
    local baseUp = type(base.upgrades) == "table" and base.upgrades or DEFAULT_RULES.upgrades
    out.upgrades = {
        engine = choice(up.engine, { "none", "street", "sport", "race" }, baseUp.engine or "race"),
        induction = choice(up.induction, { "none", "factory", "allow" }, baseUp.induction or "allow"),
        engineConversion = bool(up.engineConversion, baseUp.engineConversion ~= false),
        drivetrainConversion = choice(up.drivetrainConversion, { "off", "fwdrwd", "any" }, baseUp.drivetrainConversion or "any"),
        compound = choice(up.compound, { "road", "sport", "semi", "slick" }, baseUp.compound or "slick"),
        width = choice(tonumber(up.width), { 0, 20, 40 }, tonumber(baseUp.width) or 40),
        weight = choice(up.weight, { "none", "street", "sport", "race" }, baseUp.weight or "race"),
        brakes = choice(up.brakes, { "factory", "sport", "race" }, baseUp.brakes or "race"),
        radiators = bool(up.radiators, baseUp.radiators ~= false),
    }
    if out.centreSplitMin > out.centreSplitMax then
        out.centreSplitMin, out.centreSplitMax = out.centreSplitMax, out.centreSplitMin
    end
    if out.piMin and out.piMax and out.piMin > out.piMax then out.piMin, out.piMax = out.piMax, out.piMin end
    return out
end

local function save()
    local file = io.open(rulesFile, "w")
    if not file then
        log("Could not write " .. rulesFile)
        return false
    end
    file:write(Util.JsonPrettify(Util.JsonEncode(rules)))
    file:close()
    return true
end

local function load()
    local data = readJson(rulesFile)
    rules.default = sanitize(data and data.default)
    rules.races = {}
    if data and type(data.races) == "table" then
        for raceID, raceRules in pairs(data.races) do
            rules.races[tostring(raceID)] = sanitize(raceRules, rules.default)
        end
    end
    if not data then
        save()
        log("Created " .. rulesFile .. " with default rules")
    end
end

local function encodeRules()
    local json = Util.JsonEncode({ default = rules.default, races = rules.races })
    -- an empty Lua table encodes as []; clients expect an object
    return (json:gsub('"races":%[%]', '"races":{}'))
end

-- BeamMP logins have been down for months, so everyone joins as a random
-- guest. A guest connecting from this machine (127.0.0.1) is the server
-- owner: the one BeamJoy player record in the "owner" group. BeamJoyCore is
-- patched the same way (server/beamjoy-patch, localhost owner block).
local function localOwner(playerID)
    local okGuest, guest = pcall(MP.IsPlayerGuest, playerID)
    local okIds, ids = pcall(MP.GetPlayerIdentifiers, playerID)
    local ip = okIds and type(ids) == "table" and ids.ip or nil
    if not (okGuest and guest) or (ip ~= "127.0.0.1" and ip ~= "::1") then
        return nil
    end
    local okList, files = pcall(FS.ListFiles, beamJoyDb .. "/players")
    local owner, count = nil, 0
    for _, file in pairs(okList and files or {}) do
        if tostring(file):match("%.json$") then
            local p = readJson(beamJoyDb .. "/players/" .. file)
            if p and p.group == "owner" then owner, count = p, count + 1 end
        end
    end
    return count == 1 and owner or nil
end

-- BeamJoy's own data: player group -> group level -> SetConfig level
local function canEdit(playerID)
    if host.enabled then return host.canEdit(playerID) end
    local name = MP.GetPlayerName(playerID)
    if not name or name == "" then
        return false
    end
    local player = readJson(beamJoyDb .. "/players/" .. name .. ".json") or localOwner(playerID)
    local groups = readJson(beamJoyDb .. "/groups.json")
    local permissions = readJson(beamJoyDb .. "/permissions.json")
    if not player or not groups or not permissions then
        return false
    end
    local group = groups[player.group or ""]
    local level = group and tonumber(group.level)
    local needed = tonumber(permissions.SetConfig) or 5
    return level ~= nil and level >= needed
end

-- Motorsport settings (motorsport.json, Motorsport settings tab): who may start
-- race weekends, edit rules and track settings, and use race control, by
-- BeamJoy group, plus the race weekend defaults (MotorsportSettings.lua).
-- Player groups come from BJR's API (players.online, refreshed every 10 s);
-- before that answer, or without the API, BeamJoy's SetConfig decides.
local MotorsportSettings = dofile(pluginPath .. "/MotorsportSettings.lua")
local settingsFile = pluginPath .. "/motorsport.json"
local function bjGroups()
    local g = readJson(beamJoyDb .. "/groups.json")
    return g and g[1] and g or nil -- BJR keeps a list in rank order
end
local motorsport = MotorsportSettings.sanitize(readJson(settingsFile), bjGroups())
local playerGroups = {} -- playerID -> BeamJoy group name
local function allowedTo(playerID, action)
    local group = playerGroups[tonumber(playerID)]
    if group then return MotorsportSettings.allowed(motorsport, action, group, bjGroups()) end
    return canEdit(playerID) == true
end
local function abilities(playerID)
    local out = {}
    for _, action in ipairs(MotorsportSettings.ACTIONS) do out[action] = allowedTo(playerID, action) end
    return out
end
local sentAbilities = {}
local releaseUpdates -- ReleaseUpdates.lua, set up below: updates and optional mods
local function sendMotorsport(playerID)
    local a = abilities(playerID)
    sentAbilities[tostring(playerID)] = Util.JsonEncode(a)
    -- staff who can change rules also see optional mods still missing / out of date
    local optional = a.rules and releaseUpdates and releaseUpdates.optionalView() or nil
    MP.TriggerClientEvent(playerID, "RacePrepMotorsport", Util.JsonEncode({ settings = motorsport,
        groups = MotorsportSettings.groupNames(bjGroups()), abilities = a, group = playerGroups[tonumber(playerID)],
        optional = optional }))
end
function RacePrepGetMotorsport(playerID) sendMotorsport(playerID) end
function RacePrepSetMotorsport(playerID, data)
    if not allowedTo(playerID, "rules") and not allowedTo(playerID,"manageCrews") then
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Not saved: your BeamJoy group cannot change Motorsport settings.")
        return
    end
    local ok, p = pcall(Util.JsonDecode, data or "")
    if not ok or type(p) ~= "table" then return end
    local nextSettings,why=MotorsportSettings.patch(motorsport,p,bjGroups(),allowedTo(playerID,'rules'),allowedTo(playerID,'manageCrews'))
    if not nextSettings then MP.TriggerClientEvent(playerID,'RacePrepRulesStatus',why);return end
    if nextSettings.seasons.mode=='custom' then
        local ends=MotorsportSettings.customEnd(nextSettings.seasons.customEnd)
        local c=features.league and features.league.view(nil,nil,false).current
        local repeats=c and c.settings.mode=='custom' and c.settings.customEnd==nextSettings.seasons.customEnd
        if not ends or (ends<=os.time() and not repeats) then MP.TriggerClientEvent(playerID,'RacePrepRulesStatus','Not saved: choose a future custom season end date (YYYY-MM-DD).');return end
    end
    if not Persistence.write(settingsFile,nextSettings) then
        MP.TriggerClientEvent(playerID,"RacePrepRulesStatus","Not saved: previous Motorsport settings retained.");return
    end
    motorsport=nextSettings
    log((MP.GetPlayerName(playerID) or tostring(playerID)) .. " saved Motorsport settings")
    for pid in pairs(MP.GetPlayers() or {}) do sendMotorsport(pid) end
    MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Motorsport settings saved.")
end
MP.RegisterEvent("RacePrepGetMotorsport", "RacePrepGetMotorsport")
MP.RegisterEvent("RacePrepSetMotorsport", "RacePrepSetMotorsport")

function RacePrepGetRules(playerID, _)
    MP.TriggerClientEvent(playerID, "RacePrepRules", encodeRules())
end

function RacePrepSetRules(playerID, data)
    local name = MP.GetPlayerName(playerID) or tostring(playerID)
    if host.enabled and not host.fresh() then
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Not saved: waiting for the BeamJoy-Revived plugin API (BJR 2.0 or newer, started with the server).")
        return
    end
    if not allowedTo(playerID, "rules") then
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Not saved: your BeamJoy group cannot edit race rules (Motorsport settings > Permissions).")
        log(name .. " tried to change rules without permission")
        return
    end
    local ok, payload = pcall(Util.JsonDecode, data or "")
    if not ok or type(payload) ~= "table" or type(payload.scope) ~= "string" then
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Not saved: invalid request.")
        return
    end

    local message
    if payload.scope == "default" then
        rules.default = sanitize(payload.rules)
        message = "Server default rules saved."
    elseif type(payload.rules) == "table" then
        rules.races[payload.scope] = sanitize(payload.rules, rules.default)
        message = "Rules saved for this race."
    else
        rules.races[payload.scope] = nil
        message = "This race now uses the server default rules."
    end

    if save() then
        log(name .. ": " .. message .. " (" .. payload.scope .. ")")
        MP.TriggerClientEvent(-1, "RacePrepRules", encodeRules())
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", message)
    else
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Not saved: the server could not write rules.json.")
    end
end

---------------------------------------------------------------- race history
-- Every driver's game sends the results when a race finishes; the first copy
-- of each race (raceID + start time) is kept: history/<date>_<race>.json and
-- one row per driver in history/results.csv.

local historyDir = pluginPath .. "/history"
local resultHistory=dofile(pluginPath..'/ResultHistory.lua').new{
    path=historyDir,read=readJson,
    blocked=function(driver,run) return features.moderation and features.moderation.blocked(driver,run) end,
    list=function(path) local ok,list=pcall(FS.ListFiles,path);return ok and list or {} end,
}
local historyRequests={}
function RacePrepGetHistory(playerID)
    if not MP.GetPlayerName(playerID) then return end
    local now=os.time()
    if historyRequests[playerID] and now-historyRequests[playerID]<5 then return end
    historyRequests[playerID]=now
    local payload=resultHistory.view(host.level)
    -- Bound the response as well as the file scan, even for huge old races.
    local out={};for k,v in pairs(payload) do out[k]=v end
    out.rivalGroups=nil;out.keys=nil
    if allowedTo(playerID,"raceControl") and features.moderation then out.rivalsBlocked=features.moderation.list() end
    if features.challenges then out.featured=features.challenges.publicRotations() end
    out.seriesCars=features.catalogue and features.catalogue.list() or {}
    out.rivals,out.rivalsTruncated=Rivals.view(payload.rivalGroups or {},rivalsDriver and rivalsDriver(playerID),features.moderation and features.moderation.blocked)
    out.items={};for i,v in ipairs(payload.items) do
        local item=Persistence.copy(v)
        for _,row in ipairs(item.rows or {}) do row.rivalDriver=nil end
        out.items[i]=item
    end
    local wire=Util.JsonEncode(out)
    while #wire>1800000 and #out.rivals>0 do table.remove(out.rivals);out.rivalsTruncated=true;wire=Util.JsonEncode(out) end
    while #wire>2000000 and #out.items>0 do table.remove(out.items);wire=Util.JsonEncode(out) end
    MP.TriggerClientEvent(playerID,'RacePrepHistory',wire)
end
MP.RegisterEvent('RacePrepGetHistory','RacePrepGetHistory')
-- Each driver's game sends its copy. Their keys can differ (BeamJoy's start
-- time is shifted by each client's own clock offset), so copies are matched
-- by race id: the first copy within DUPLICATE_WINDOW_S of another is kept.
local DUPLICATE_WINDOW_S = 90
local lastSavedAt = {}
local lastAcceptedResult

local function csvField(v)
    v = tostring(v == nil and "" or v)
    if v:find('[,"\n]') then
        v = '"' .. v:gsub('"', '""') .. '"'
    end
    return v
end

local function msText(ms)
    if type(ms) ~= "number" then
        return ""
    end
    return string.format("%.3f", ms / 1000)
end

function RacePrepRaceResult(playerID, data)
    if host.enabled and not trustedNativeResult then return false end
    local ok, res = pcall(Util.JsonDecode, data or "")
    if not ok or type(res) ~= "table" or type(res.rows) ~= "table" or type(res.key) ~= "string" then
        return
    end
    -- Only the dedicated server-observation writer may create verification proof.
    res.verified=false;res.verification=nil
    if raceControl then raceControl.applyPenalties(res) end
    local raceKey = tostring(res.raceID or res.raceName or res.key)
    if res.runID and (trustedNativeResult or (raceControl and raceControl.validRun(res))) then raceKey=raceKey .. ":" .. tostring(res.runID) end
    local now = os.time()
    if res.runID and resultHistory.contains(res) then return false end
    if lastSavedAt[raceKey] and now - lastSavedAt[raceKey] < DUPLICATE_WINDOW_S then
        return false
    end
    if not FS.Exists(historyDir) then
        FS.CreateDirectory(historyDir)
    end
    local stamp = os.date("%Y-%m-%d_%H%M%S")
    local name = tostring(res.raceName or res.raceID or "race"):gsub("[^%w%-_]+", "_")
    local suffix=res.runID and ("_"..tostring(res.runID):gsub("[^%w_%-]","_"):sub(1,96)) or ""
    res.completedAt=now
    if res.source=='bjr-api' then features.awards.result(res) end
    local resultPath=historyDir .. "/" .. stamp .. "_" .. name .. suffix .. ".json"
    if not Persistence.write(resultPath,res) then
        logWarn('Result NOT saved: '..resultPath..'; it remains eligible for retry.')
        return false
    end
    features.awards.clear(res.runID)
    lastSavedAt[raceKey]=now
    resultHistory.invalidate()
    local csvPath = historyDir .. "/results.csv"
    local isNew = not FS.Exists(csvPath)
    local csv = io.open(csvPath, "a")
    if csv then
        if isNew then
            csv:write("date,race,laps,position,driver,car,status,laps_done,total_s,gap_s,best_lap_s,best_lap_no\n")
        end
        for _, row in ipairs(res.rows) do
            if type(row) == "table" then
                csv:write(table.concat({
                    csvField(res.date), csvField(res.raceName), csvField(res.laps), csvField(row.position),
                    csvField(row.name), csvField(row.car), csvField(row.status), csvField(row.laps),
                    msText(row.total), msText(row.gap),
                    type(row.best) == "table" and msText(row.best.time) or "",
                    type(row.best) == "table" and csvField(row.best.lap) or "",
                }, ",") .. "\n")
            end
        end
        csv:close()
    end
    if raceControl then raceControl.recordResult(res) end
    log("Saved results of " .. tostring(res.raceName) .. " (" .. #res.rows .. " drivers)")
    lastAcceptedResult = res
    if features.discord then features.discord.enqueue(res) end
    return true
end

MP.RegisterEvent("RacePrepGetRules", "RacePrepGetRules")
MP.RegisterEvent("RacePrepRaceResult", "RacePrepRaceResult")
MP.RegisterEvent("RacePrepSetRules", "RacePrepSetRules")
load()
log("Loaded rules from " .. rulesFile)

---------------------------------------------------------------- shared ratings
-- Rating sync payloads. The full store goes to a player once (join / request);
-- changes go to everyone as small deltas. Before, every computed rating, car
-- mapping, deleted car and disconnect re-sent the whole store (every entry
-- with its parts list) to all players. Measured seed entries ship with the
-- client mod, so their parts lists stay out of the payload (client restores).
local function wireEntry(e,key)
    -- measured entries and native estimates ship in every client's seed:
    -- their parts lists come from there (keeps the join payload small)
    if type(e)~='table' then return e end
    local meta=ratingPresentations and ratingPresentations[key]
    local strip=(e.source=='measured' or e.estimate) and e.parts~=nil
    if not meta and not strip then return e end
    local c={}
    for k,v in pairs(e) do if k~='parts' or not strip then c[k]=v end end
    c.presentation=meta
    return c
end
local function encodeRatings()
    local entries={}
    for k,e in pairs(ratings.entries) do entries[k]=wireEntry(e,k) end
    return Util.JsonEncode({ schemaVersion=1, entries=entries, constants=ratings.constants,
        vehicles=ratingVehicles }):gsub('"vehicles":%[%]', '"vehicles":{}')
end
-- entries: {[key]=entry}; vehicles: {[pid]={[sid]=key|false}} or {[pid]=false}
local function encodeDelta(entries,vehicles)
    local out={}
    for k,e in pairs(entries or {}) do out[k]=wireEntry(e,k) end
    return (Util.JsonEncode({ schemaVersion=1, delta=true, entries=out, vehicles=vehicles or {} })
        :gsub('"entries":%[%]','"entries":{}'):gsub('"vehicles":%[%]','"vehicles":{}'))
end
local function saveRatings()
    local file=io.open(ratingsFile..'.tmp','w')
    if not file then return false end
    local ok=pcall(function() file:write(Util.JsonPrettify(Util.JsonEncode(ratings))) end)
    file:close()
    if not ok then os.remove(ratingsFile..'.tmp');return false end
    return os.rename(ratingsFile..'.tmp',ratingsFile)~=nil
end
function RacePrepGetRatings(playerID)
    if ratings then MP.TriggerClientEvent(playerID,'RacePrepRatings',encodeRatings()) end
end
function RacePrepComputedRating(playerID,data)
    if type(data)~='string' or #data>1048576 or not MP.GetPlayerName(playerID) then return end
    -- Per-player burst budget; cached repeat announcements are cheap but bounded.
    local now=os.time()
    local budget=ratingReports[playerID]
    if not budget or now-budget.at>=10 then budget={at=now,count=0};ratingReports[playerID]=budget end
    budget.count=budget.count+1
    if budget.count>20 then return end
    local ok,p=pcall(Util.JsonDecode,data)
    if not ok or type(p)~='table' then return end
    local sid=type(p.serverVehicleID)=='string' and p.serverVehicleID or ''
    local owner,veh=sid:match('^(%d+)%-(%d+)$')
    if tonumber(owner)~=tonumber(playerID) then return end
    -- Confirm this is one of the sender's network vehicles when the API exists.
    if MP.GetPlayerVehicles then
        local vehicles=MP.GetPlayerVehicles(playerID)
        if type(vehicles)~='table' or not (vehicles[tonumber(veh)] or vehicles[veh]) then return end
        local raw=vehicles[tonumber(veh)] or vehicles[veh]
        if type(raw)=='string' then
            local json=raw:match('({.*)$')
            local parsed,vehicleData=pcall(Util.JsonDecode,json or '')
            if parsed and type(vehicleData)=='table' and vehicleData.jbm and vehicleData.jbm~=p.model then return end
        end
    end
    local e,key
    if p.parts==nil and type(p.key)=='string' then
        -- short report: a rating the server already holds, named by its key.
        -- Re-sending the full parts list made BeamMP allocate a 30 MB unpack
        -- buffer per report ("zlib uncompress() failed", 2026-10-21)
        key=p.key
        e=#key<=600 and type(p.model)=='string' and key:sub(1,#p.model+1)==p.model..'/' and ratings.entries[key] or nil
        if not e then MP.TriggerClientEvent(playerID,'RacePrepRatingMissing',sid);return end
    else
        e,key=RatingStore.validate(p,RatingIdentity,ratings and ratings.constants)
        if not e then return end
    end
    -- an anchored rating replaces an older blind computed one for the same parts
    local old=ratings.entries[key]
    local changed=not old or (old.source=='computed' and not old.anchored and e.anchored==true)
    if changed then
        ratings.entries[key]=e
        if not saveRatings() then ratings.entries[key]=nil;log('Could not persist computed rating');return end
    end
    if features.autoRatings then features.autoRatings.accept(playerID,p,key)end
    local pid=tostring(playerID)
    local meta=RatingStore.presentation(p)
    local oldMeta=ratingPresentations[key]
    local viewChanged=meta and (not oldMeta or meta.tuningShare~=oldMeta.tuningShare or meta.weightShare~=oldMeta.weightShare or meta.carName~=oldMeta.carName)
    if meta then ratingPresentations[key]=meta end
    ratingVehicles[pid]=ratingVehicles[pid] or {}
    local mappingChanged=ratingVehicles[pid][sid]~=key
    ratingVehicles[pid][sid]=key
    if changed or mappingChanged or viewChanged then
        MP.TriggerClientEvent(-1,'RacePrepRatings',encodeDelta((changed or viewChanged) and {[key]=ratings.entries[key]} or nil,{[pid]={[sid]=key}}))
        refreshCars(playerID)
        -- A setup can change between periodic grid reports. Refresh only the
        -- exact previously identified grid car; freeze its PI at countdown.
        local runID=host.runFor(playerID);local run=runID and host.runs[runID]
        local fitted=runID and (host.gridRatings[runID] or {})[pid]
        if run and run.phase=='grid' and fitted and fitted.serverVehicleID==sid and not (bjrApi and bjrApi.gridLocked and bjrApi.gridLocked(runID)) then
            local view=displayRating(key)
            host.gridRatings[runID][pid]={pi=view.pi,class=view.class,model=view.model,car=view.carName or view.model,ratingKey=key,serverVehicleID=sid}
            local racerKey=host.racerKeyFor(playerID,runID)
            if racerKey then host.gridRatings[runID]['racer:'..racerKey]=host.gridRatings[runID][pid] end
            if bjrApi and bjrApi.setCarFields then bjrApi.setCarFields(runID,playerID,view) end
        end
    end
end
function RacePrepSetRating(playerID,data)
    if not canEdit(playerID) then MP.TriggerClientEvent(playerID,'RacePrepRulesStatus','Rating not saved: SetConfig permission required.');return end
    local ok,p=pcall(Util.JsonDecode,data or '')
    if not ok then return end
    local e,key=RatingStore.validate(p,RatingIdentity,ratings and ratings.constants)
    if not e then return end
    local old=ratings.entries[key]
    if old and old.source~='computed' and old.source~='admin' then
        MP.TriggerClientEvent(playerID,'RacePrepRulesStatus','Measured and calibrated ratings are protected.');return
    end
    e.source='admin';ratings.entries[key]=e
    if saveRatings() then MP.TriggerClientEvent(-1,'RacePrepRatings',encodeDelta({[key]=e},nil))
    else ratings.entries[key]=old end
end
-- Large client events arrive in uncompressed pieces (client raceprep/net.lua:
-- packets over 400 bytes are zlib-compressed and BeamMP retries their unpack
-- with a 30 MB buffer). One message in flight per player, pieces in order
-- (TCP); joined, it fires the original RacePrep event.
local chunks={}
function RacePrepChunk(playerID,data)
    if type(data)~='string' then return end
    local id,i,n,event,body=data:match('^(%d+)|(%d+)|(%d+)|(RacePrep[%w_]+)|(.*)$')
    i,n=tonumber(i),tonumber(n)
    if not id or event=='RacePrepChunk' or not i or not n or n<1 or n>4096 or i>n then chunks[playerID]=nil;return end
    local c=chunks[playerID]
    if i==1 then c={id=id,event=event,n=n,parts={},size=0};chunks[playerID]=c end
    if not c or c.id~=id or c.event~=event or c.n~=n or #c.parts~=i-1 then chunks[playerID]=nil;return end
    c.parts[i]=body;c.size=c.size+#body
    if c.size>1048576 then chunks[playerID]=nil;return end
    if i==n then chunks[playerID]=nil;MP.TriggerLocalEvent(event,playerID,table.concat(c.parts)) end
end
MP.RegisterEvent('RacePrepChunk','RacePrepChunk')
function RacePrepRatingDisconnect(playerID)
    chunks[playerID]=nil
    historyRequests[playerID]=nil
    ratingVehicles[tostring(playerID)]=nil;ratingReports[playerID]=nil
    if ratings then MP.TriggerClientEvent(-1,'RacePrepRatings',encodeDelta(nil,{[tostring(playerID)]=false})) end
end
function RacePrepRatingVehicleDeleted(playerID,vehID)
    local group=ratingVehicles[tostring(playerID)]
    local sid=tostring(playerID)..'-'..tostring(vehID)
    if group then group[sid]=nil end
    if ratings then MP.TriggerClientEvent(-1,'RacePrepRatings',encodeDelta(nil,{[tostring(playerID)]={[sid]=false}})) end
    refreshCars(playerID)
end
ratings=readJson(ratingsFile) or readJson(pluginPath..'/ratings-seed.json')
if not ratings or type(ratings.entries)~='table' or not ratings.constants then
    error('BJR:ME: ratings.json/ratings-seed.json missing or invalid')
end
-- Seed migration: a store saved by an older build lacks newer seed ratings
-- (e.g. BeamNG cars). Seed entries replace missing, computed and older
-- measured ones; admin-set ratings are kept.
-- kept as shipped: renamed saved setups find their factory base in it, the
-- same choice the client's anchorSelection makes
local ratingSeed=readJson(pluginPath..'/ratings-seed.json')
do
    local merged,dropped=RatingStore.mergeSeed(ratings,ratingSeed)
    if dropped>0 then log('Dropped '..dropped..' computed ratings anchored to an older measured stock rating; they are recomputed on spawn') end
    log('Rating seed merged into the store: '..merged..' entries')
end
MP.RegisterEvent('RacePrepGetRatings','RacePrepGetRatings')
MP.RegisterEvent('RacePrepComputedRating','RacePrepComputedRating')
MP.RegisterEvent('RacePrepSetRating','RacePrepSetRating')
MP.RegisterEvent('onPlayerJoin','RacePrepGetRatings')
MP.RegisterEvent('onPlayerDisconnect','RacePrepRatingDisconnect')
MP.RegisterEvent('onVehicleDeleted','RacePrepRatingVehicleDeleted')
log('Loaded shared car ratings from '..ratingsFile)

---------------------------------------------------------------- skill rating
-- Elo-style driver rating from the race results (see Skill.lua): keyed by
-- BeamMP account, or a salted hash of the IP for guests (IPs are not
-- stored). Car performance (PI) is taken into account. skills.json next to
-- this file; "aliases" there merges two profiles of the same person.

local Skill = dofile(pluginPath .. "/Skill.lua")
local skillsFile = pluginPath .. "/skills.json"
local skills = readJson(skillsFile)
if type(skills) ~= "table" or type(skills.players) ~= "table" then
    skills = Skill.newStore()
end
skills.aliases = type(skills.aliases) == "table" and skills.aliases or {}
skills.salt = skills.salt or Skill.newSalt()
local lastDeltas = {}

local function saveSkills()
    local ok=Persistence.write(skillsFile,skills)
    if not ok then logWarn('Could not save skill ratings; previous file retained.') end
    return ok
end
-- Persist the identity salt even before the first multiplayer result.
if not FS.Exists(skillsFile) then saveSkills() end

local function skillKey(playerID)
    local ok, ids = pcall(MP.GetPlayerIdentifiers, playerID)
    if ok then
        return Skill.key(skills, ids)
    end
end

rivalsDriver=function(pid)
 local key=skillKey(tonumber(pid));return key and Skill.hash(skills.salt,key)
end

local function resultIdentity(runID,pid,row)
    local saved=host.racerIdentities[tostring(runID)] or {}
    return (row and row.racerKey and saved[tostring(row.racerKey)]) or (tonumber(pid) and skillKey(tonumber(pid)))
end

-- the car's PI: the player's current rated vehicle, else the car model
local function rowPI(row)
    if host.enabled then return tonumber(row.pi) end
    local pid = tostring(row.playerID)
    for _, key in pairs(ratingVehicles[pid] or {}) do
        local e = displayRating(key)
        if e and (not row.model or e.model == row.model) and tonumber(e.pi) then
            return tonumber(e.pi)
        end
    end
    local best
    for _, e in pairs(ratings.entries or {}) do
        if row.model and e.model == row.model and tonumber(e.pi) then
            local c = RatingStore.present(e, nil, ratings.constants)
            if e.measured then return tonumber(c.pi) end
            best = best or tonumber(c.pi)
        end
    end
    return best
end

local function encodeSkills()
    local out = {}
    for pid in pairs(MP.GetPlayers() or {}) do
        local key = skillKey(pid)
        if key then
            local p = skills.players[key]
            out[tostring(pid)] = { rating = p and p.rating or Skill.START, races = p and p.races or 0,
                score = features.rating.score(p and p.rating or Skill.START),
                scoreDelta = lastDeltas[key] and math.floor(lastDeltas[key]*4/3+.5), delta = lastDeltas[key] }
        end
    end
    local json = Util.JsonEncode(out)
    return json == "[]" and "{}" or json
end

function RacePrepGetSkills(playerID)
    MP.TriggerClientEvent(playerID, "RacePrepSkills", encodeSkills())
end

function RacePrepSkillsJoin(playerID)
    MP.TriggerClientEvent(-1, "RacePrepSkills", encodeSkills())
end

local skillPendingFile=pluginPath..'/skill-pending.json'
local skillPending=readJson(skillPendingFile) or {}
skills.seen=skills.seen or {}
local function flushSkills()
 for key,job in pairs(skillPending) do
  if skills.seen[key] then skillPending[key]=nil
  else
   local before=Persistence.copy(skills)
   local deltas=Skill.update(skills,job.entries,job.at)
   skills.seen[key]=true
   if saveSkills() then lastDeltas=deltas;skillPending[key]=nil
   else skills=before end
  end
 end
 Persistence.write(skillPendingFile,skillPending)
 MP.TriggerClientEvent(-1,'RacePrepSkills',encodeSkills())
end
local baseRaceResult = RacePrepRaceResult
function RacePrepRaceResult(playerID, data)
 if baseRaceResult(playerID,data)~=true then return end
 local res=lastAcceptedResult
 local entries,seen={},{}
 for _,row in ipairs(res.rows or {}) do
  local key=resultIdentity(res.runID,tonumber(row.playerID),row)
  if key and not seen[key] then seen[key]=true;entries[#entries+1]={key=key,name=row.name,pi=rowPI(row)} end
 end
 local key=tostring(res.runID or res.key)
 if #entries>=2 and not skills.seen[key] then
  skillPending[key]={entries=entries,at=os.time()}
  if not Persistence.write(skillPendingFile,skillPending) then logWarn('Skill retry queue could not be saved; keep the server running until storage is available.') end
  flushSkills()
 end
end
function RacePrepRetrySkills() if next(skillPending) then flushSkills() end end
MP.RegisterEvent('RacePrepRetrySkills','RacePrepRetrySkills')
MP.CreateEventTimer('RacePrepRetrySkills',5000)

MP.RegisterEvent("RacePrepGetSkills", "RacePrepGetSkills")
MP.RegisterEvent("onPlayerJoin", "RacePrepSkillsJoin")

---------------------------------------------------------------- sessions + grid order
-- Practice and qualifying before a race (see Sessions.lua). An admin
-- (SetConfig) starts them from BeamJoy's Race Settings; they run in free roam
-- on that race's checkpoints, read from BeamJoy's race files. Qualifying sets
-- the grid through the BeamJoyCore patch (server/beamjoy-patch); without it
-- the grid stays in join order and admins are told so.

local Sessions = dofile(pluginPath .. "/Sessions.lua")
local Weekend = dofile(pluginPath .. "/Weekend.lua")
local weekend = nil      -- the race weekend (Weekend.lua): practice -> qualifying -> grid -> race
local nativePhaseView = nil -- BJR-owned timing for the weekend tab; never a local lap tracker
local session = nil      -- running session
local sessionTrack = nil -- {level, steps, startPositions} of the running session
local pendingSession = nil -- {at, raceID, level, type, minutes} (event: qualifying after practice)
local lastQuali = {}     -- raceID -> {view, at}
local gridCars = {}      -- raceID -> {playerID -> pi}
local gridPatch = false  -- BeamJoyCore patch answered
local sessionCounter = 0

local function raceRules(raceID,sessionID)
    local selected=features.presets and features.presets.session(sessionID)
    if selected then return selected.rules end
    return rules.races[host.enabled and (tostring(host.level)..":"..tostring(raceID)) or tostring(raceID)] or rules.default
end

features.catalogue=dofile(pluginPath..'/SeriesCatalogue.lua').new{path=pluginPath,
 client=pluginPath:gsub('Resources/Server/RacePrep$','Resources/Client'),read=readJson,exists=FS.Exists,now=os.time}
features.presets=dofile(pluginPath..'/EventPresets.lua').new{
 cars=function() return features.catalogue.list() end,hasModel=features.catalogue.has,
 read=function() return readJson(pluginPath..'/presets.json') end,exists=function() return FS.Exists(pluginPath..'/presets.json') end,
 write=function(s) return Persistence.write(pluginPath..'/presets.json',s) end,sanitize=function(p) return sanitize(p,DEFAULT_RULES) end,
 eligibility=function(pid,raceID)
  if not MP.GetPlayerName(pid) or not host.fresh() or not (host.names or {})[tostring(pid)] then return 'Waiting for your BJR player profile.' end
  if host.runFor(pid) then return 'Leave your current BJR session before opening a race.' end
  if features.rivalsSessions and features.rivalsSessions.active(pid) then return 'End your Rivals run before opening a race.' end
  local race=host.race(host.level,raceID);if not race then return 'This layout is not available on the current map.' end
  if race.mode and race.mode~='grid' then return 'Choose a grid race layout.' end
 end,
}
function RacePrepGetPresets(pid)
 if not MP.GetPlayerName(pid) then return end
 local view=features.presets.view(allowedTo(pid,'rules'));view.sessions=features.presets.sessions()
 MP.TriggerClientEvent(pid,'RacePrepPresets',Util.JsonEncode(view))
end
function RacePrepPresetAction(pid,wire)
 if not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>20000 then return end
 local ok,p=pcall(Util.JsonDecode,wire);if not ok or type(p)~='table' then return end
 local now=os.time();features.presetRequests=features.presetRequests or {}
 if features.presetRequests[pid] and now-features.presetRequests[pid]<1 then return end;features.presetRequests[pid]=now
 local saved,why
 if p.action=='open' then
  saved,why=features.presets.open(pid,p,function(selected)
   if not (bjrApi and bjrApi.call) then MP.TriggerClientEvent(pid,'RacePrepRulesStatus','BJR race API unavailable.');return end
   bjrApi.call('race.open',{raceId=tonumber(selected.raceID),name=selected.preset.name,
    options={laps=selected.laps,allowTuning=selected.rules.tuning}},function(opened,result)
    if not opened then MP.TriggerClientEvent(pid,'RacePrepRulesStatus',type(result)=='table' and (result.message or result.code) or tostring(result));return end
    if not features.presets.assign(result.sessionId,selected) then
     bjrApi.call('race.close',{sessionId=result.sessionId,reason='Preset rules could not be saved.'},function()end)
     MP.TriggerClientEvent(pid,'RacePrepRulesStatus','Lobby closed: preset rules could not be saved.');return
    end
    for player in pairs(MP.GetPlayers() or {}) do RacePrepGetPresets(player) end
    MP.TriggerClientEvent(pid,'RacePrepRulesStatus','Lobby opened: '..selected.preset.name..'. Join and Ready in BJR.')
   end)
  end)
  if saved then return end
 else saved,why=features.presets.action(p,allowedTo(pid,'rules')) end
 if saved then for player in pairs(MP.GetPlayers() or {}) do RacePrepGetPresets(player) end end
 MP.TriggerClientEvent(pid,'RacePrepRulesStatus',saved and 'Preset library saved.' or why or 'Preset refused.')
end
MP.RegisterEvent('RacePrepGetPresets','RacePrepGetPresets')
MP.RegisterEvent('RacePrepPresetAction','RacePrepPresetAction')

local function readRace(level, raceID)
    if host.enabled then return host.race(level,raceID) end
    level = tostring(level or "")
    if not level:match("^[%w_%-%.]+$") then
        return nil
    end
    local races = readJson(beamJoyDb .. "/scenarii/" .. level .. "_races.json")
    for _, race in ipairs(races or {}) do
        if tostring(race.id) == tostring(raceID) then
            return race
        end
    end
end

local function sessionPayload()
    if host.enabled and nativePhaseView then
        local payload={};for k,v in pairs(nativePhaseView) do payload[k]=v end
        payload.weekend=Weekend.view(weekend)
        return Util.JsonEncode(payload)
    end
    if not session then
        return Util.JsonEncode({ state = "none", gridPatch = gridPatch, weekend = Weekend.view(weekend) })
    end
    local view = Sessions.view(session, os.time())
    view.weekend = Weekend.view(weekend)
    view.track = sessionTrack
    view.trackLimits = raceRules(session.raceID).trackLimits
    view.gridPatch = gridPatch
    view.gridOrder = raceRules(session.raceID).gridOrder
    return Util.JsonEncode(view)
end

local function broadcastSession(target)
    MP.TriggerClientEvent(target or -1, "RacePrepSession", sessionPayload())
end

-- grid order for a race (qualifying, reverse top N, handicap); nil = BeamJoy's own.
-- A qualifying result sets the grid until that race is run or a new weekend
-- starts. A weekend whose grid order was chosen at its start overrides the rule.
local function gridOrderFor(raceID, level, qualifying, racers, bjrSession)
    local r = raceRules(raceID,bjrSession and bjrSession.sessionId)
    local q = not bjrCan('phases') and lastQuali[tostring(raceID)] or nil
    if qualifying then q={view=qualifying,at=os.time()} end
    if q and level and q.view.level and q.view.level ~= level then q = nil end
    if weekend and weekend.gridOrder and weekend.raceID == tostring(raceID) and
      (not bjrSession or tostring(weekend.sessionId)==tostring(bjrSession.sessionId)) then
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        copy.gridOrder = weekend.gridOrder
        r = copy
    end
    local cars=gridCars[tostring(raceID)]
    if host.enabled and racers then
        cars={}
        for _,rr in ipairs(racers) do
            local ratings=host.gridRatings[tostring(bjrSession and bjrSession.sessionId or '')] or {}
            local fitted=ratings['racer:'..tostring(rr.racerKey)] or ratings[tostring(rr.id)]
            fitted=fitted or ((weekend and host.gridRatings[tostring(weekend.sessionId)] or {})[tostring(rr.id)])
            fitted=fitted or ((weekend and host.gridRatings[tostring(weekend.sessionId)] or {})['racer:'..tostring(rr.racerKey)])
            local key=rr.racerKey or rr.id
            if key~=nil and fitted and fitted.pi then cars[tostring(key)]=fitted.pi end
        end
    end
    local order
    if (r.gridOrder=='skill' or r.gridOrder=='safety') and host.enabled and racers then
        local ranked={}
        for i,rr in ipairs(racers) do
            local identity=(host.racerIdentities[tostring(bjrSession and bjrSession.sessionId)] or {})[tostring(rr.racerKey)] or (rr.id and skillKey(rr.id))
            local skill=identity and skills.players[identity]
            local profile=raceControl and raceControl.driverProfile(identity)
            local value=r.gridOrder=='skill' and (skill and skill.races>=5 and features.rating.score(skill.rating) or -1) or (profile and (profile.safetyRaces or 0)>=5 and profile.safety or -1)
            ranked[#ranked+1]={racerKey=rr.racerKey,value=value,join=i}
        end
        table.sort(ranked,function(a,b) if a.value~=b.value then return a.value>b.value end;return a.join<b.join end)
        order={};for _,rr in ipairs(ranked) do if rr.racerKey then order[#order+1]={racerKey=rr.racerKey} end end
    else order=Sessions.gridOrder(r.gridOrder,q and q.view,cars,r.gridReverseTop) end
    if host.enabled then
        for _,e in ipairs(order or {}) do e.racerKey=e.racerKey or (e.playerID and tostring(e.playerID));e.playerID=nil end
    end
    return order, r
end
local lastGridOrder = {}
local lastHostStatusAt = -1e9
local function pushGridOrder(raceID, level)
    if host.enabled then return end -- BJR: the gridOrder hook (BJRApi.lua) asks for the order itself
    local order, r = gridOrderFor(raceID, level)
    local parts = {}
    for i, e in ipairs(order or {}) do parts[i] = tostring(e.playerID) .. ":" .. tostring(e.pi or "") end
    local targetLevel = level or host.level
    local key = tostring(targetLevel) .. ":" .. tostring(raceID)
    local sig = tostring(r.gridOrder) .. "|" .. table.concat(parts, ",")
    if lastGridOrder[key] == sig then return end
    lastGridOrder[key] = sig
    MP.TriggerGlobalEvent("RacePrepGridOrder", Util.JsonEncode({ raceID = tostring(raceID), level=targetLevel, mode=r.gridOrder, order = order or {} }))
end

local function savePhase(view)
    if not FS.Exists(historyDir) then
        FS.CreateDirectory(historyDir)
    end
    local name = tostring(view.raceName or view.raceID):gsub("[^%w%-_]+", "_")
    local kind=tostring(view.type or 'session'):lower():gsub('[^%w_%-]','_')
    local file = io.open(historyDir .. "/" .. os.date("%Y-%m-%d_%H%M%S") .. "_" .. name .. "_" .. tostring(view.id):gsub("[^%w_%-]","_") .. "_"..kind..".json", "w")
    if file then
        file:write(Util.JsonPrettify(Util.JsonEncode(view)))
        file:close()
    end
end

local function startSession(raceID, level, kind, minutes, nextKind, nextMinutes)
    local race = readRace(level, raceID)
    if not race or type(race.steps) ~= "table" or #race.steps == 0 then
        return false, "Race " .. tostring(raceID) .. " not found for map " .. tostring(level)
    end
    sessionCounter = sessionCounter + 1
    session = Sessions.new(tostring(os.time()) .. "-" .. sessionCounter, raceID, race.name, kind, minutes, os.time())
    session.level = level
    session.variableSectors = race.nativeRace ~= nil
    session.nextKind = nextKind
    session.nextMinutes = nextMinutes
    sessionTrack = { level = level, steps = race.steps, startPositions = race.startPositions, loopable = race.loopable, nativeRace = race.nativeRace }
    log(string.format("%s started: %s (%d min)", Sessions.TYPES[kind], tostring(race.name), minutes))
    broadcastSession()
    return true
end

-- the weekend's grid, once qualifying (or practice without one) is over
local function weekendToGrid()
    if not weekend then return end
    weekend.stage = "grid"
    local order = gridOrderFor(weekend.raceID, weekend.level)
    weekend.grid = Weekend.gridList(order)
    pushGridOrder(weekend.raceID, weekend.level)
    log("Race weekend: grid set for " .. tostring(weekend.raceName) .. ", waiting for the race lobby")
    if host.enabled then
        -- BJR without phases has no race.open: a player opens the lobby in BeamJoy's race menu
        MP.TriggerClientEvent(-1, "RacePrepRulesStatus", "Qualifying is over: open the race lobby for " .. tostring(weekend.raceName) ..
            " in BeamJoy's race menu" .. (weekend.by and (" (" .. tostring(weekend.by) .. " started this weekend)") or "") .. ". The grid follows qualifying.")
    end
end

local function endSession()
    local s = session
    local view = Sessions.view(s, os.time())
    log(string.format("%s ended: %s (%d drivers)", view.label, tostring(view.raceName), #view.rows))
    if s.type == "qualifying" then
        lastQuali[s.raceID] = { view = view, at = os.time() }
        savePhase(view)
        pushGridOrder(s.raceID,s.level)
    end
    if weekend and weekend.raceID == s.raceID and weekend.stage == s.type then
        local nextKind, minutes = Weekend.after(weekend, s.type)
        if nextKind == "grid" then weekendToGrid()
        else pendingSession = { at = os.time(), raceID = s.raceID, level = s.level, type = nextKind, minutes = minutes } end
    end
end

--- a race weekend: {raceID, level, practiceMinutes, qualifyingMinutes, gridOrder}
--- (gridOrder only when the settings let it be chosen at the start)
function RacePrepWeekendStart(playerID, data)
    if not allowedTo(playerID, "weekend") then
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Your BeamJoy group cannot start a race weekend.")
        return
    end
    local ok, p = pcall(Util.JsonDecode, data or "")
    if not ok or type(p) ~= "table" or p.raceID == nil then return end
    local level = p.level or host.level
    local race = readRace(level, p.raceID)
    if not race then
        MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", "Race " .. tostring(p.raceID) .. " not found on this map.")
        return
    end
    local w = motorsport.weekend
    local gridOrder = nil
    if w.gridSource == "weekend" then
        for _, g in ipairs(MotorsportSettings.GRID_ORDERS) do if p.gridOrder == g then gridOrder = g end end
    end
    -- from the race's rules; a race left on BeamJoy's join order takes the
    -- weekend default instead, or its qualifying would set nothing
    if not gridOrder then
        local rule = raceRules(p.raceID).gridOrder
        gridOrder = (rule and rule ~= "join") and rule or w.gridOrder
    end
    if host.enabled and not (bjrApi and bjrApi.caps) then
        MP.TriggerClientEvent(playerID,"RacePrepRulesStatus","BeamJoy-Revived's plugin API is not ready yet; try again in a moment.");return
    end
    local phased=bjrCan('phases')
    if session and session.state ~= "ended" then session.state = "ended"; session.nextKind = nil end
    session, pendingSession, nativePhaseView = nil, nil, nil
    lastQuali[tostring(p.raceID)] = nil -- a new weekend: the old qualifying no longer counts
    weekend = Weekend.new({ raceID = p.raceID, level = level, raceName = race.name,
        practiceMinutes = number(p.practiceMinutes, w.practiceMinutes, 0, 120),
        qualifyingMinutes = number(p.qualifyingMinutes, w.qualifyingMinutes, 0, 120),
        raceLaps = number(p.raceLaps, w.raceLaps or 5, 1, 1000),
        gridOrder = gridOrder, by = MP.GetPlayerName(playerID) }, os.time())
    -- classic: BJR:ME times practice and qualifying, the race is a normal BJR lobby
    weekend.mode = phased and 'phases' or 'classic'
    weekend.byID = playerID
    if phased then
        weekend.stage='grid'
        local opening=weekend
        bjrApi.openWeekend({raceID=p.raceID,name='BJR:ME weekend: '..tostring(race.name),practiceMinutes=weekend.practiceMinutes,
          qualifyingMinutes=weekend.qualifyingMinutes,raceLaps=weekend.raceLaps},function(opened,result)
            if weekend~=opening then return end
            if not opened then
                local message=type(result)=='table' and (result.message or result.code) or result
                weekend=nil;broadcastSession();MP.TriggerClientEvent(playerID,'RacePrepRulesStatus','Weekend not opened: '..tostring(message));return
            end
            weekend.sessionId=result.sessionId;weekend.phaseIndex=result.phaseIndex or 1;weekend.phaseCount=result.phaseCount or weekend.phaseCount
            Weekend.update(weekend,result,'grid');broadcastSession()
            MP.TriggerClientEvent(playerID,'RacePrepRulesStatus','BJR:ME weekend lobby opened. Join and ready in BeamJoy.')
        end)
        log('BJR:ME weekend requested by '..tostring(opening.by)..': '..tostring(race.name));broadcastSession();return
    end
    local kind, minutes = Weekend.first(weekend)
    log("Race weekend started by " .. tostring(weekend.by) .. ": " .. tostring(race.name))
    if kind == "grid" then weekendToGrid()
    else
        weekend.stage = kind
        local started, err = startSession(weekend.raceID, level, kind, minutes)
        if not started then weekend = nil; MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", err); return end
    end
    broadcastSession()
    MP.TriggerClientEvent(playerID, "RacePrepRulesStatus", host.enabled and "Race weekend started (classic: BJR:ME times practice and qualifying)." or "Race weekend started.")
end

--- skip to the next stage (practice -> qualifying -> grid)
function RacePrepWeekendNext(playerID)
    if not allowedTo(playerID, "weekend") or not weekend then return end
    if weekend.mode=='phases' and bjrApi and bjrApi.call and weekend.sessionId then
        bjrApi.call('race.endPhase',{sessionId=weekend.sessionId},function(ok,err)
          MP.TriggerClientEvent(playerID,'RacePrepRulesStatus',ok and 'Current phase ended.' or ('Could not end phase: '..tostring(err and (err.message or err.code) or err)))
        end);return
    end
    if session and session.state ~= "ended" and weekend.stage == session.type then
        session.state = "ended"
        endSession() -- moves the weekend on
    elseif weekend.stage ~= "race" and weekend.stage ~= "ended" then
        weekendToGrid()
    end
    broadcastSession()
end

function RacePrepWeekendEnd(playerID)
    if not allowedTo(playerID, "weekend") then return end
    if weekend and weekend.mode=='phases' and weekend.sessionId and bjrApi and bjrApi.call then
        bjrApi.call('race.close',{sessionId=weekend.sessionId,reason='Weekend ended by staff'})
    end
    pendingSession = nil
    if session and session.state ~= "ended" then
        session.state = "ended"
        session.nextKind = nil
    end
    if weekend then
        lastQuali[weekend.raceID] = nil
        log("Race weekend ended by " .. tostring(MP.GetPlayerName(playerID)))
    end
    weekend = nil;nativePhaseView=nil
    broadcastSession()
end

--- BJR started / finished a race (API events): the weekend follows its race
local function weekendRaceStarted(raceID)
    if Weekend.raceStarted(weekend, raceID) then broadcastSession() end
end
local function weekendRaceFinished(raceID,runID)
    -- classic: another lobby on this track finishing during practice/qualifying is not the weekend's race
    if weekend and weekend.mode=='classic' and weekend.stage~='grid' and weekend.stage~='race' and tostring(raceID)==weekend.raceID then return end
    lastQuali[tostring(raceID)] = nil -- the race was run: its qualifying is used up
    if weekend and runID and weekend.sessionId and tostring(weekend.sessionId)~=tostring(runID) then return end
    if Weekend.raceFinished(weekend, raceID) then
        log("Race weekend finished: " .. tostring(weekend.raceName))
        weekend = nil;nativePhaseView=nil
        broadcastSession()
    end
end

function RacePrepLap(playerID, data)
    if not session or session.state == "ended" then
        return
    end
    local ok, lap = pcall(Util.JsonDecode, data or "")
    if not ok or type(lap) ~= "table" or lap.sessionID ~= session.id then
        return
    end
    if Sessions.addLap(session, playerID, MP.GetPlayerName(playerID), lap, os.time()) then
        broadcastSession()
        -- session laps lay rubber too (rubber stays on the map)
        local metres = tonumber(lap.distance)
        if raceControl and raceControl.addRubber and metres and metres > 0 then
            raceControl.addRubber(session.level, math.min(metres, 30000))
        end
    end
end

function RacePrepGetSession(playerID)
    broadcastSession(playerID)
end

-- BeamJoy groups for the Motorsport permissions (BJR API players.online)
local nextGroups = 0
local function refreshGroups()
    if not (bjrApi and bjrApi.call) or os.time() < nextGroups then return end
    nextGroups = os.time() + 10
    bjrApi.call("players.online", {}, function(ok, result)
        if not ok or type(result) ~= "table" or type(result.players) ~= "table" then return end
        host.setPlayers(result.players)
        local seen = {}
        for _, p in ipairs(result.players) do
            local id = tonumber(p.id)
            if id then
                seen[id] = true
                local newlyResolved=playerGroups[id]==nil
                playerGroups[id] = type(p.group) == "string" and p.group or nil
                local now = Util.JsonEncode(abilities(id))
                if sentAbilities[tostring(id)] ~= now then sendMotorsport(id) end
                if newlyResolved and RacePrepProgressJoin then RacePrepProgressJoin(id) end
            end
        end
        for id in pairs(playerGroups) do if not seen[id] then playerGroups[id] = nil; sentAbilities[tostring(id)] = nil end end
    end)
end

function RacePrepSessionTick()
    refreshGroups()
    if pendingSession and os.time() >= pendingSession.at then
        local p = pendingSession
        pendingSession = nil
        if weekend and weekend.raceID == tostring(p.raceID) then weekend.stage = p.type end
        startSession(p.raceID, p.level, p.type, p.minutes, nil)
        broadcastSession()
    end
    if not session or session.state == "ended" then
        return
    end
    local change = Sessions.tick(session, os.time())
    if change == "ended" then
        endSession()
    end
    if change then
        broadcastSession()
    end
end

-- a driver on a BeamJoy race grid reports the car's PI (handicap grids) and
-- triggers the grid order for that race
function RacePrepGridCar(playerID, data)
    local ok, p = pcall(Util.JsonDecode, data or "")
    if not ok or type(p) ~= "table" or p.raceID == nil then
        return
    end
    local key = tostring(p.raceID)
    if host.enabled then
        local runID=host.runFor(playerID);local state=runID and host.runs[runID]
        if not state or state.phase~='grid' or tostring(state.raceID)~=key then return end
        if bjrApi and bjrApi.gridLocked and bjrApi.gridLocked(runID) then return end
        local ratingKey=(ratingVehicles[tostring(playerID)] or {})[p.serverVehicleID]
        local e=ratingKey and displayRating(ratingKey)
        if e then
            host.gridRatings[runID]=host.gridRatings[runID] or {}
            local fitted={pi=e.pi,class=e.class,model=e.model,car=e.carName or e.model,config=e.config,ratingKey=ratingKey,serverVehicleID=p.serverVehicleID}
            host.gridRatings[runID][tostring(playerID)]=fitted
            local racerKey=host.racerKeyFor(playerID,runID);if racerKey then host.gridRatings[runID]['racer:'..racerKey]=fitted end
            if bjrApi and bjrApi.setCarFields then bjrApi.setCarFields(runID,playerID,e) end
        end
    end
    gridCars[key] = gridCars[key] or {}
    gridCars[key][tostring(playerID)] = tonumber(p.pi) or 0
    pushGridOrder(key, p.level)
    if not gridPatch and not host.enabled then
        MP.TriggerGlobalEvent("RacePrepGridOrderPing", "")
    end
end

function RacePrepGridOrderPatch(wire)
    if host.enabled and type(wire)~="string" then return end
    if not gridPatch then
        gridPatch = true
        lastGridOrder = {}
        -- on BeamJoy-Revived the answer comes from BJR:ME's own bridge file and the
        -- grid order goes through BJR's gridOrder hook (logged by the API): nothing
        -- to report. Only the original BeamJoy (v1) needs its BeamJoyCore patch.
        if not host.enabled then log("BeamJoy v1: BeamJoyCore grid order patch found") end
    end
end

-- track-limit cuts during a BeamJoy race: relayed so every game's results
-- know them
function RacePrepCut(playerID, data)
    local ok, p = pcall(Util.JsonDecode, data or "")
    if ok and type(p) == "table" then
        if host.enabled then
            local cut=host.cut(playerID,p,raceRules(p.raceID,host.runFor(playerID)));if not cut then return end
            p.racerKey=cut.racerKey;p.cuts=cut.cuts
            if cut.penaltyMs>0 and bjrApi and bjrApi.penalize and not localPenalties() then
                bjrApi.penalize(cut.runID,cut.racerKey,cut.penaltyMs,'Track limits',function(accepted,err)
                  if not accepted then log('BJR track-limit penalty refused: '..tostring(err and (err.message or err.code) or err)) end
                end)
            end
        end
        p.playerID = playerID
        MP.TriggerClientEvent(-1, "RacePrepCut", Util.JsonEncode(p))
    end
end

function RacePrepSessionDisconnect(playerID)
    for _, cars in pairs(gridCars) do
        cars[tostring(playerID)] = nil
    end
end

MP.RegisterEvent("RacePrepWeekendStart", "RacePrepWeekendStart")
MP.RegisterEvent("RacePrepWeekendNext", "RacePrepWeekendNext")
MP.RegisterEvent("RacePrepWeekendEnd", "RacePrepWeekendEnd")
MP.RegisterEvent("RacePrepLap", "RacePrepLap")
MP.RegisterEvent("RacePrepGetSession", "RacePrepGetSession")
MP.RegisterEvent("RacePrepGridCar", "RacePrepGridCar")
MP.RegisterEvent("RacePrepGridOrderPatch", "RacePrepGridOrderPatch")
MP.RegisterEvent("RacePrepCut", "RacePrepCut")
MP.RegisterEvent("onPlayerDisconnect", "RacePrepSessionDisconnect")
MP.RegisterEvent("RacePrepSessionTick", "RacePrepSessionTick")
MP.CreateEventTimer("RacePrepSessionTick", 1000)
-- upgrade parts for cars added since the last start (PartsUpdater.lua)
local partsUpdater=dofile(pluginPath.."/PartsUpdater.lua")
function RacePrepPartsPoll() if partsUpdater.poll() then MP.CancelEventTimer("RacePrepPartsPoll") end end
if partsUpdater.start({path=pluginPath,exists=FS.Exists,read=readJson,remove=os.remove,execute=os.execute,getenv=os.getenv,
    now=os.time,osName=MP.GetOSName and MP.GetOSName() or "",log=log,logWarn=logWarn}) then
    MP.RegisterEvent("RacePrepPartsPoll","RacePrepPartsPoll")
    MP.CreateEventTimer("RacePrepPartsPoll",1000)
end
if not host.enabled then MP.TriggerGlobalEvent("RacePrepGridOrderPing", "") end -- BeamJoy v1's BeamJoyCore patch

-- BJR:ME release updates (ReleaseUpdates.lua): console commands and a periodic
-- check for new releases. Release checks never rewrite live plugins or the
-- download ZIP. Set up once at plugin start.
local function writeJson(path, value)
    local file = io.open(path .. ".tmp", "w")
    if not file then return false end
    file:write(Util.JsonPrettify(Util.JsonEncode(value)));file:close()
    os.remove(path) -- Windows cannot rename over an existing file
    return os.rename(path .. ".tmp", path) and true or false
end
releaseUpdates=dofile(pluginPath..'/ReleaseUpdates.lua').new({path=pluginPath,exists=FS.Exists,read=readJson,write=writeJson,
    execute=os.execute,now=os.time,windows=MP.GetOSName and MP.GetOSName()=='Windows',log=log})
-- Motorsport settings: "Don't remind me" for one optional mod
function RacePrepOptionalIgnore(playerID, data)
    local ok, p = pcall(Util.JsonDecode, data or "")
    local key = ok and type(p) == "table" and p.key
    if not allowedTo(playerID, "rules") or type(key) ~= "string" then return end
    if releaseUpdates.ignore(key, true) then
        log((MP.GetPlayerName(playerID) or tostring(playerID)) .. " turned off reminders for optional mod " .. key)
        for pid in pairs(MP.GetPlayers() or {}) do sendMotorsport(pid) end
    end
end
MP.RegisterEvent('RacePrepOptionalIgnore','RacePrepOptionalIgnore')
function RacePrepConsoleUpdates(input) return releaseUpdates.command(input) end
function RacePrepUpdateCheckTick() releaseUpdates.tick() end
MP.RegisterEvent('onConsoleInput','RacePrepConsoleUpdates')
MP.RegisterEvent('RacePrepUpdateCheckTick','RacePrepUpdateCheckTick')
MP.CreateEventTimer('RacePrepUpdateCheckTick',1000)

-- the current map's track weather through BJR's weather sync (BJRApi.syncWeather):
-- sent when BJR's API is up, when the map changes and when an admin saves it
local weatherLevel
local function syncWeather()
    if not (bjrApi and bjrApi.syncWeather and raceControl and raceControl.weatherFor and host.level) then return end
    weatherLevel = host.level
    bjrApi.syncWeather(raceControl.weatherFor(host.level))
end
raceControl = dofile(pluginPath .. "/RaceControl.lua").new({rules=raceRules,path=pluginPath,
 canEdit=function(pid) return allowedTo(pid,"rules") end,canControl=function(pid) return allowedTo(pid,"raceControl") end,
 identity=skillKey,resultIdentity=resultIdentity,localPenalties=localPenalties,read=readJson,race=readRace,host=host,onTrack=syncWeather,
 progressionSnapshot=function(res)
  if not features.league then return end
  local ids={};for _,row in ipairs(res.rows or {}) do local key=resultIdentity(res.runID,tonumber(row.playerID),row);if key then ids[#ids+1]=Skill.hash(skills.salt,key) end end
  return features.league.snapshot(ids)
 end,
 progression=function(job,profiles)
  if not features.progress then return end
  local rows={}
  for _,row in ipairs(job.result.rows or {}) do
   local key=job.identities[tostring(row.racerKey or row.playerID)];local p=key and profiles.drivers[key]
   if p then rows[#rows+1]={id=Skill.hash(skills.salt,key),name=p.name,profile=Persistence.copy(p),row=Persistence.copy(row),skill=features.rating.score((skills.players[key] or {}).rating or Skill.START)} end
  end
  features.progress.record(job.result,rows,job.safety,job.progressionSnapshot)
 end,
 penalize=function(sessionId,racerKey,ms,reason)
  if bjrApi and bjrApi.penalize then bjrApi.penalize(sessionId,racerKey,ms,reason,function(ok,err)
   if not ok then log('BJR penalty refused: '..tostring(err and (err.message or err.code) or err)) end
  end) end
 end})

-- BeamJoy-Revived's state comes from its plugin API (BJRHost.lua): its race
-- sessions every second, players every 10 s, the map from server.info /
-- MapChanged, race layouts from its saved race files. BJR:ME adds nothing to
-- BJR's folders (the former bridge file is gone since 2.14.2).
host.loadRaces=function(level)
 level=tostring(level or '')
 if not level:match('^[%w_%-%.]+$') then return nil end
 local list=readJson(beamJoyDb..'/activities/'..level..'_races.json')
 local n=0;for _ in ipairs(list or {}) do n=n+1 end
 log(string.format("BJR race layouts read: %s (%d race%s)", level, n, n==1 and '' or 's'))
 return list
end
local function hostTick()
 if session and session.state~='ended' and session.level~=host.level then
  pendingSession=nil;session.state='ended';session.nextKind=nil;endSession();broadcastSession()
 end
 raceControl.snapshot({phase='none',level=host.level,participants={}})
 if host.level~=weatherLevel then syncWeather() end
 for id,state in pairs(host.runs) do
  if not rivalContexts[id] or state.phase=='grid' then
   local layout=host.race(state.level or host.level,state.raceID)
   if layout then rivalContexts[id]={layout=Skill.hash('layout',Rivals.canonical({level=state.level or host.level,gates=layout.gates,loopable=layout.loopable,branchingEnabled=layout.branchingEnabled})),
    rulesKey=ChallengeCatalogue.rulesKey(Skill.hash,raceRules(state.raceID,id),(features.presets.session(id) or {}).preset),preset=(features.presets.session(id) or {}).preset,rules=Persistence.copy(raceRules(state.raceID,id))} end
  end
  raceControl.snapshot(state)
 end
 for id in pairs(rivalContexts) do if not host.runs[id] then rivalContexts[id]=nil end end
 local now=os.time()
 if now-lastHostStatusAt>=2 then
  lastHostStatusAt=now
  MP.TriggerClientEvent(-1,'RacePrepBJRHostStatus','ready')
 end
end
function RacePrepHostPoll()
 if not (host.enabled and bjrApi and bjrApi.call and host.level) then return end
 bjrApi.call('races.sessions',{},function(ok,result)
  if not ok or type(result)~='table' then return end
  host.setRuns(host.fromSessions(result.sessions,os.time()*1000))
  for _,s in ipairs(result.sessions or {}) do
   local id=tostring(s.sessionId)
   host.racerIdentities[id]=host.racerIdentities[id] or {}
   for _,r in ipairs(s.racers or {}) do
    if r.id~=nil and r.racerKey then
     local key=tostring(r.racerKey)
     host.racerIdentities[id][key]=host.racerIdentities[id][key] or skillKey(r.id)
    end
   end
   if not weekend then weekend=Weekend.fromSession(s,os.time()) end
   if weekend and tostring(s.sessionId)==tostring(weekend.sessionId) then
    Weekend.update(weekend,s,s.state=='BREAK' and 'break' or s.state=='GRID' and 'grid' or nil)
    nativePhaseView=Weekend.phaseView(s,os.time()*1000)
    broadcastSession()
   end
  end
  local done,err=pcall(hostTick);if not done then log('BJR state: '..tostring(err)) end
 end)
end
MP.RegisterEvent('RacePrepHostPoll','RacePrepHostPoll')
MP.CreateEventTimer('RacePrepHostPoll',1000)
features.progress=dofile(pluginPath..'/Progression.lua').new{
 read=function(name) return readJson(pluginPath..'/'..name) end,exists=function(name) return FS.Exists(pluginPath..'/'..name) end,
 write=function(name,value) return Persistence.write(pluginPath..'/'..name,value) end,copy=Persistence.copy,
 settings=function() return motorsport end,log=log,
 reward=function(id,receipt)
  for pid in pairs(MP.GetPlayers() or {}) do if rivalsDriver(pid)==id then MP.TriggerClientEvent(pid,'RacePrepReward',Util.JsonEncode(receipt));return end end
 end,
 blocked=function(id,run) return features.moderation and features.moderation.blocked(id,run) end,
 deferEvents=true,
 snapshot=function(rows,res)
  if not features.league then return end
  local ids={};for _,r in ipairs(rows) do ids[#ids+1]=r.id end
  for _,r in ipairs(res.rows or {}) do if r.rivalDriver then ids[#ids+1]=r.rivalDriver end end
  return features.league.snapshot(ids)
 end,
 event=function(job) return features.league and features.league.score(job) or false end,
 pole=function(run) return (features.qualifyingPole or {})[tostring(run)] end,
 startPole=function(run) return (features.racePole or {})[tostring(run)] end,
}
local function sendPlayerProgress(pid,ids,groups)
 local league=features.league and features.league.view(ids[tostring(pid)],nil,false)
 features.progress.send(pid,features.progress.payload(pid,ids,league,groups),Util.JsonEncode,MP.TriggerClientEvent)
end
function RacePrepProgressJoin(pid)
 if not MP.GetPlayerName(pid) then return end
 local ids={}
 for player,name in pairs(MP.GetPlayers() or {}) do
  local key=skillKey(tonumber(player));local id=key and Skill.hash(skills.salt,key)
  if id then
   if tostring(player)==tostring(pid) then features.progress.refresh(id,name,raceControl.driverProfile(key),features.rating.score((skills.players[key] or {}).rating or Skill.START)) end
   ids[tostring(player)]=id
  end
 end
 if ids[tostring(pid)] then sendPlayerProgress(pid,ids,resultHistory.view(host.level).rivalGroups) end
end
MP.RegisterEvent('onPlayerJoin','RacePrepProgressJoin')
function RacePrepGetProgress(pid)
 features.progressReadAt=features.progressReadAt or {};local now=os.time()
 if features.progressReadAt[pid]==now then return end
 features.progressReadAt[pid]=now;RacePrepProgressJoin(pid)
end
MP.RegisterEvent('RacePrepGetProgress','RacePrepGetProgress')
function RacePrepProgressTick()
 if features.progressAt and os.time()-features.progressAt<4 then return end;features.progressAt=os.time()
 if not raceControl.pendingRecords() then features.progress.flush() end
 if features.league and not features.progress.pending() and not raceControl.pendingRecords() then features.league.tick() end
 if not raceControl.pendingRecords() then features.progress.medals(resultHistory.view(host.level).rivalGroups) end
 local ids={};local players=MP.GetPlayers() or {};local groups=resultHistory.view(host.level).rivalGroups
 for pid,name in pairs(players) do
  local key=skillKey(tonumber(pid));local id=key and Skill.hash(skills.salt,key)
  if id then
   features.progress.refresh(id,name,raceControl.driverProfile(key),features.rating.score((skills.players[key] or {}).rating or Skill.START))
   ids[tostring(pid)]=id
  end
 end
 for pid in pairs(players) do
  sendPlayerProgress(pid,ids,groups)
 end
end
MP.RegisterEvent('RacePrepProgressTick','RacePrepProgressTick');MP.CreateEventTimer('RacePrepProgressTick',5000)
-- BJR plugin API bridge (BJRApi.lua), set below when BJR has an API
local railPage=false -- BJR's menu rail shows the Motorsport page
-- fromApi: BJR's RaceFinished event (BJRApi.lua); BJR's API events only come
-- from BJR's server VM, so the host's run check is not needed for them
local function nativeResult(res,fromApi)
 for _,row in ipairs(res.rows or {}) do
  local ratings=host.gridRatings[tostring(res.runID)] or host.gridRatings[res.runID] or {}
  local fitted=(row.racerKey and ratings['racer:'..tostring(row.racerKey)]) or ratings[tostring(row.playerID)]
  row.pi=fitted and fitted.pi or row.pi;row.class=row.pi and RatingStore.classOf(row.pi)
  if fitted then row.car=fitted.car or row.car;row.model=fitted.model or row.model end
 end
 local selected=features.presets.session(res.runID);if selected then res.preset=Persistence.copy(selected.preset) end
 host.results(res,raceRules(res.raceID,res.runID),localPenalties())
 weekendRaceFinished(res.raceID,res.runID)
 local context=rivalContexts[tostring(res.runID)]
 -- A staff rule edit during the run makes it incomparable with either
 -- fixed-rule challenge. Preserve the race result, omit its Rivals entry.
 if context and context.rulesKey==ChallengeCatalogue.rulesKey(Skill.hash,raceRules(res.raceID,res.runID),res.preset) then
  res.recordContext=Persistence.copy(context)
 else res.recordContext=nil end
 for _,row in ipairs(res.rows or {}) do
  local key=resultIdentity(res.runID,tonumber(row.playerID),row)
  row.rivalDriver=key and Skill.hash(skills.salt,key)
  local skill=key and skills.players[key];local profile=raceControl and raceControl.driverProfile(key)
  row.driverRating={score=features.rating.score(skill and skill.rating or Skill.START),provisional=not skill or skill.races<5,
   safety=features.rating.grade(profile and profile.safety or 3),safetyProvisional=not profile or (profile.safetyRaces or 0)<5}
  local rr=(host.gridRatings[tostring(res.runID)] or {})
  local fitted=(row.racerKey and rr['racer:'..tostring(row.racerKey)]) or rr[tostring(row.playerID)]
  row.buildKey=fitted and fitted.ratingKey and Skill.hash('build',fitted.ratingKey)
  for _,lap in ipairs(row.lapList or {}) do lap.class=row.class;lap.pi=row.pi;lap.model=row.model;lap.buildKey=row.buildKey end
 end
 local wire=Util.JsonEncode(res)
 trustedNativeResult=true
 local success,err=pcall(RacePrepRaceResult,-1,wire)
 trustedNativeResult=false
 if not success then log(err);return end
 local targets=host.fresh() and host.targets(res.runID) or {}
 if fromApi and #targets==0 then for _,row in ipairs(res.rows or {}) do if row.playerID then targets[#targets+1]=tonumber(row.playerID) end end end
 if lastAcceptedResult and tostring(lastAcceptedResult.runID)==tostring(res.runID) then res=lastAcceptedResult end
 local public=Persistence.copy(res);for _,row in ipairs(public.rows or {}) do row.rivalDriver=nil end
 for _,pid in ipairs(targets) do MP.TriggerClientEvent(pid,'RacePrepBJRResults',Util.JsonEncode(public)) end
end
-- Catalogue comes from current generator inputs plus shipped native base models.
features.available=function(g)
 local race=host.race(host.level,g.raceID)
 return race and g.layout==Skill.hash('layout',Rivals.canonical({level=host.level,gates=race.gates,loopable=race.loopable,branchingEnabled=race.branchingEnabled})) and
  g.rulesKey==Skill.hash('rules',Rivals.canonical(raceRules(g.raceID)))
end
features.discord=dofile(pluginPath..'/DiscordAwards.lua').new{path=pluginPath,now=os.time,read=readJson,exists=FS.Exists,
 write=Persistence.write,encode=Util.JsonEncode,copy=Persistence.copy,execute=os.execute,log=log,token=function(id) return Skill.hash('award-job',id) end}
function RacePrepAwardsTick() features.discord.tick() end
MP.RegisterEvent('RacePrepAwardsTick','RacePrepAwardsTick');MP.CreateEventTimer('RacePrepAwardsTick',2000)
-- Per-player Rivals sessions use the existing race catalogue and ratings.
local function currentRatedCar(pid,sid)
 local key=type(sid)=='string' and (ratingVehicles[tostring(pid)] or {})[sid]
 local e=key and displayRating(key)
 if e then return {key=key,vehicle=sid,model=e.model,car=e.carName or e.model,class=e.class,pi=e.pi,config=e.config} end
end
features.verification=dofile(pluginPath..'/RivalsVerification.lua')
features.nativeIdentity=dofile(pluginPath..'/NativeIdentity.lua').new{read=readJson,path=pluginPath,hash=RatingIdentity.hash}
features.position=dofile(pluginPath..'/RivalsBeamMP.lua').new(MP,Util.JsonDecode,Rivals.canonical,features.verification)
features.moderation=dofile(pluginPath..'/RivalsModeration.lua').new{
 now=os.time,read=function() return readJson(pluginPath..'/rivals-moderation.json') end,
 exists=function() return FS.Exists(pluginPath..'/rivals-moderation.json') end,
 write=function(v) return Persistence.write(pluginPath..'/rivals-moderation.json',v) end,copy=Persistence.copy,
 allowed=function(pid) return allowedTo(pid,'raceControl') end,actor=rivalsDriver,log=log,
 name=function(driver)
  for _,g in pairs(resultHistory.view(host.level).rivalGroups or {}) do
   for _,r in pairs(g.bests) do if r.driver==driver then return r.name end end
  end
 end,
 known=function(driver,run,action)
  if action=='unblock' then return features.moderation.blocked(driver) end
  for _,g in pairs(resultHistory.view(host.level).rivalGroups or {}) do
   for _,r in pairs(g.bests) do if r.driver==driver and (action~='remove' or r.runID==run) then return true end end
  end
  return false
 end,changed=function() resultHistory.invalidate();if features.rivalInbox then features.rivalInbox.prune();RacePrepRivalNoticeTick() end end,
}
features.challenges=ChallengeCatalogue.new{
 now=os.time,copy=Persistence.copy,hash=Skill.hash,level=function() return host.level end,
 read=function() return readJson(pluginPath..'/challenges.json') end,exists=function() return FS.Exists(pluginPath..'/challenges.json') end,
 write=function(v) return Persistence.write(pluginPath..'/challenges.json',v) end,
 settings=function() return motorsport.challenges end,blocked=features.moderation.blocked,
 race=function(id) return host.race(host.level,id) end,races=function() if not host.fresh() then return {} end;return host.races end,
 rules=raceRules,preset=features.presets.get,presets=function() return features.presets.view(false).items end,presetRules=features.presets.rules,
 layout=function(r) return Skill.hash('layout',Rivals.canonical({level=host.level,gates=r.gates,loopable=r.loopable,branchingEnabled=r.branchingEnabled})) end,
 band=function(c) return dofile(pluginPath..'/EventPresets.lua').band(c) end,
 classes=function() local seen,out={},{};for _,e in pairs(ratings.entries or {}) do if e.class and features.catalogue.has(e.model) then seen[e.class]=true end end;for _,c in ipairs({'E','D','C','B','A','S','R','P','X'})do if seen[c]then out[#out+1]=c end end;return out end,
 groups=function() return resultHistory.view(host.level).rivalGroups end,
}
features.available=features.challenges.available
local challengeRequests={}
function RacePrepGetChallenges(pid,wire)
 if not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>2048 then return end
 local now=os.time();local budget=challengeRequests[pid]
 if not budget or budget.at~=now then budget={at=now,n=0};challengeRequests[pid]=budget end
 budget.n=budget.n+1;if budget.n>8 then return end
 local ok,q=pcall(Util.JsonDecode,wire);if not ok or type(q)~='table' then return end
 local out=features.challenges.page(q,rivalsDriver(pid));out.featured,out.error=features.challenges.publicRotations();out.presets=features.presets.view(false).items
 MP.TriggerClientEvent(pid,'RacePrepChallenges',Util.JsonEncode(out))
end
MP.RegisterEvent('RacePrepGetChallenges','RacePrepGetChallenges')
features.league=dofile(pluginPath..'/League.lua').new{
 now=os.time,settings=function() return motorsport end,copy=Persistence.copy,log=log,
 canClose=function() return not features.progress.pending() and not raceControl.pendingRecords() end,
 read=function(n) return readJson(pluginPath..'/'..n) end,exists=function(n) return FS.Exists(pluginPath..'/'..n) end,
 write=function(n,v) return Persistence.write(pluginPath..'/'..n,v) end,
 drivers=function() return features.progress.data().drivers end,known=function(id) return type(id)=='string' and features.progress.driver(id)~=nil end,
 blocked=features.moderation.blocked,
 grant=function(awards)
  if next(awards)==nil then return true end
  return features.progress.change(function(s)
   for id,list in pairs(awards) do local d=s.drivers[id];if d then d.achievements=d.achievements or {};for a in pairs(list) do d.achievements[a]=true end end end
  end)
 end,
}
features.rivalInbox=dofile(pluginPath..'/RivalNotices.lua').new{
 read=function() return readJson(pluginPath..'/rival-notices.json') end,exists=function() return FS.Exists(pluginPath..'/rival-notices.json') end,
 write=function(v) return Persistence.write(pluginPath..'/rival-notices.json',v) end,copy=Persistence.copy,log=log,
 blocked=features.moderation.blocked,level=function() return host.level end,groups=function(level) return resultHistory.view(level).rivalGroups end,
 recordsEnabled=function() return motorsport.discordRivalsRecords==true end,
 record=function(p) features.discord.record(p) end,
 send=function(id,p) for pid in pairs(MP.GetPlayers() or {}) do if rivalsDriver(pid)==id then MP.TriggerClientEvent(pid,'RacePrepRivalNotice',Util.JsonEncode(p));return end end end,
}
features.rivalReady={};features.rivalViews={};features.rivalNoticeRequests={}
function RacePrepRivalNoticeTick()
 features.rivalInbox.prune()
 for pid in pairs(MP.GetPlayers() or {}) do if features.rivalReady[pid] then
  local id=rivalsDriver(pid)
  if id then
   if not features.rivalReady[pid].joined then if features.rivalInbox.deliver(id,'join') then features.rivalReady[pid].joined=true end
   else features.rivalInbox.deliver(id,'live') end
   local p=Util.JsonEncode({kind='state',items=features.rivalInbox.view(id)})
   if features.rivalViews[pid]~=p then MP.TriggerClientEvent(pid,'RacePrepRivalNotice',p);features.rivalViews[pid]=p end
  end
 end end
end
function RacePrepRivalNoticeAction(pid,wire)
 if not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>2048 then return end
 local ok,p=pcall(Util.JsonDecode,wire);if not ok or type(p)~='table' then return end
 local now=os.time();if features.rivalNoticeRequests[pid] and now-features.rivalNoticeRequests[pid]<1 then return end;features.rivalNoticeRequests[pid]=now
 local id=rivalsDriver(pid);if not id then return end
 if p.action=='join' then features.rivalReady[pid]=features.rivalReady[pid] or {joined=false};RacePrepRivalNoticeTick()
 elseif p.action=='ghost' and type(p.id)=='string' then
  local target,why=features.rivalInbox.target(id,p.id)
  if target then MP.TriggerClientEvent(pid,'RacePrepRivalGhost',Util.JsonEncode(target)) else MP.TriggerClientEvent(pid,'RacePrepRulesStatus',why) end
 end
end
MP.RegisterEvent('RacePrepRivalNotices','RacePrepRivalNoticeAction');MP.RegisterEvent('RacePrepRivalNoticeTick','RacePrepRivalNoticeTick');MP.CreateEventTimer('RacePrepRivalNoticeTick',2000)
local rivalsSessions=dofile(pluginPath..'/RivalsSessions.lua').new{
 now=os.time,clock=features.position.available() and features.position.clock or nil,
 position=features.position.available() and features.position.position or nil,config=features.position.config,
 token=function() return tostring(os.time())..'-'..tostring(Util.RandomIntRange(1,2147483646))..'-'..tostring(Util.RandomIntRange(1,2147483646)) end,
 blocked=features.moderation.blocked,level=function() return host.level end,driver=rivalsDriver,
 car=function(pid,sid)
  local c=currentRatedCar(pid,sid);local e=c and ratings.entries[c.key]
  if c and e then
   -- the seed rates BeamNG factory configs by key only; their lists ship separately
   c.parts=e.parts or (e.native and features.nativeIdentity.parts(c.key)) or nil
   -- No trustworthy measured top speed is stored for every build. The PI
   -- fallback is deliberately generous and is a plausibility filter only.
   c.speedCeiling=math.min(250,math.max(80,(tonumber(e.topSpeed) or c.pi*.2)*1.25))
  end
  return c
 end,
 factory=function(car)return features.factoryRating and features.factoryRating(car)end,group=features.challenges.get,currentRules=features.challenges.currentRules,rotation=features.challenges.rotation,
 inRace=function(pid) return not host.fresh() or host.runFor(pid)~=nil end,
 groups=function() return resultHistory.view(host.level).rivalGroups end,
 race=function(id) return host.race(host.level,id) end,rules=raceRules,
 layout=function(race) return Skill.hash('layout',Rivals.canonical({level=host.level,gates=race.gates,loopable=race.loopable,branchingEnabled=race.branchingEnabled})) end,
 rulesKey=function(r,g) return ChallengeCatalogue.rulesKey(Skill.hash,r,g and g.preset,g and g.type,g and g.options) end,build=function(key) return Skill.hash('build',key) end,
 name=function(id) local r=host.race(host.level,id);return r and r.name end,nameOf=MP.GetPlayerName,
 send=function(pid,event,p) MP.TriggerClientEvent(pid,event,Util.JsonEncode(p)) end,
 trace=function(target)
  local res=target.sourcePath and readJson(target.sourcePath)
  for _,row in ipairs(res and res.rows or {}) do if row.rivalDriver==target.driver and row.model==target.model and row.best and row.best.time==target.time then return row.best.trace end end
 end,
 save=function(res)
  local rr=res.rows[1];local cc=res.recordContext
  local previous=cc and Persistence.copy(resultHistory.view(res.level).rivalGroups[Rivals.key(cc,rr.class)])
  if not FS.Exists(historyDir) then FS.CreateDirectory(historyDir) end
  local filename=os.date('%Y-%m-%d_%H%M%S')..'_'..res.runID:gsub('[^%w_%-]','_')..'.json'
  local ok=Persistence.write(historyDir..'/'..filename,res)
  if ok then
   resultHistory.invalidate()
   local row=res.rows[1];local c=res.recordContext;local group=c and resultHistory.view(res.level).rivalGroups[Rivals.key(c,row.class)]
   local best
   for _,r in pairs(group and group.bests or {}) do if r.verified and not features.moderation.blocked(r.driver,r.runID) then best=math.min(best or math.huge,r.time) end end
   local weekly={rotations=features.challenges.rotations()}
   features.progress.rival(res,best,weekly)
   features.rivalInbox.record(res,previous);RacePrepRivalNoticeTick()
  end
  return ok
 end,
}
features.rivalsSessions=rivalsSessions
local AutoRating=dofile(pluginPath..'/AutoRating.lua')
features.ratingClients={};features.ratingViews={}
features.autoRatings=AutoRating.new{
 now=os.time,copy=Persistence.copy,localOnly=false,
 read=function() return readJson(pluginPath..'/rating-jobs.json')end,exists=function() return FS.Exists(pluginPath..'/rating-jobs.json')end,
 write=function(v)return Persistence.write(pluginPath..'/rating-jobs.json',v)end,
 cars=features.catalogue.list,rated=function(car,key)return AutoRating.rated(ratings.entries,car,key or (ratings.baselines or {})[car.model..'/'..tostring(AutoRating.config(car.config))])end,
 token=function()return tostring(os.time())..'-'..tostring(Util.RandomIntRange(1,2147483646))end,
 clients=function()
  local out={};for pid in pairs(MP.GetPlayers()or{})do
   local r=features.ratingClients[tostring(pid)];out[#out+1]={pid=pid,staff=host.permissions[tostring(pid)]==true,ready=host.fresh()and r~=nil and os.time()-r.at<6,free=host.fresh()and not host.runFor(pid),rivals=rivalsSessions.active(tonumber(pid)),idle=r and r.idle or 0}
  end;return out
 end,
 send=function(pid,p)MP.TriggerClientEvent(pid,'RacePrepAutoRatingJob',Util.JsonEncode(p))end,
}
features.factoryRating=function(car)
 local e=car and ratings.entries[car.key or car.ratingKey or ''];if not e then return end
 local key=(ratings.baselines or {})[e.model..'/'..tostring(e.config)]or features.autoRatings.defaultKey({model=e.model,config=e.config})
 if key then return ratings.entries[key] end
 -- a saved setup is named after its file, not its factory config: use the
 -- closest factory parts, as the client does (it refused Ready forever)
 local base,baseKey=AnchorSelection.select(ratingSeed or {},e.model,e.config,e.parts)
 return base and (ratings.entries[baseKey] or base)
end
function RacePrepAutoRatingTick()
 features.autoRatings.tick()
 local wire=Util.JsonEncode(features.autoRatings.view())
 for pid in pairs(MP.GetPlayers()or{})do if features.ratingClients[tostring(pid)]and features.ratingViews[tostring(pid)]~=wire then features.ratingViews[tostring(pid)]=wire;MP.TriggerClientEvent(pid,'RacePrepAutoRatingState',wire)end end
end
function RacePrepAutoRating(pid,wire)
 if not MP.GetPlayerName(pid)or type(wire)~='string'or #wire>2048 then return end
 local ok,p=pcall(Util.JsonDecode,wire);if not ok or type(p)~='table'then return end
 local key=tostring(pid);local old=features.ratingClients[key];local now=os.time()
 if p.action=='heartbeat'then
  if old and now-old.at<1 then return end
  local idle=tonumber(p.idle);if not idle or idle~=idle or idle<0 or idle>86400 then return end
  features.ratingClients[key]={at=now,idle=idle}
 elseif p.action=='rate'then
  if not allowedTo(pid,'rules')then return end
 elseif p.action=='done'or p.action=='failed'or p.action=='abort'then features.autoRatings.message(pid,p)
 else return end
 RacePrepAutoRatingTick()
end
function RacePrepAutoRatingDisconnect(pid)
 features.autoRatings.disconnect(pid);features.ratingClients[tostring(pid)]=nil;features.ratingViews[tostring(pid)]=nil
end
MP.RegisterEvent('RacePrepAutoRating','RacePrepAutoRating');MP.RegisterEvent('RacePrepAutoRatingTick','RacePrepAutoRatingTick');MP.CreateEventTimer('RacePrepAutoRatingTick',2000)
MP.RegisterEvent('onPlayerDisconnect','RacePrepAutoRatingDisconnect')
features.rivalMessages={}
function RacePrepRivals(pid,wire)
 if not host.enabled or not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>600000 then return end
 local now=os.time();local budget=features.rivalMessages[pid]
 if not budget or budget.at~=now then budget={at=now,n=0};features.rivalMessages[pid]=budget end
 budget.n=budget.n+1;if budget.n>10 then return end
 local ok,p=pcall(Util.JsonDecode,wire);if ok then rivalsSessions.handle(pid,p) end
end
function RacePrepRivalsDisconnect(pid)
 features.rivalReady[pid]=nil;features.rivalViews[pid]=nil;features.rivalNoticeRequests[pid]=nil
 rivalsSessions.disconnect(pid);features.position.disconnect(pid);features.moderation.disconnect(pid);features.rivalMessages[pid]=nil
end
function RacePrepRivalsPoll() rivalsSessions.poll() end
function RacePrepRivalsReset(pid,vid) rivalsSessions.vehicleEvent(pid,vid,'Reset') end
function RacePrepRivalsEdited(pid,vid) rivalsSessions.vehicleEvent(pid,vid,'parts / tune edited') end
function RacePrepRivalsDeleted(pid,vid) rivalsSessions.vehicleEvent(pid,vid,'vehicle deleted') end
function RacePrepRivalsModerate(pid,wire)
 if not host.enabled or not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>2048 then return end
 local ok,p=pcall(Util.JsonDecode,wire)
 local saved=ok and features.moderation.handle(pid,p)
 MP.TriggerClientEvent(pid,'RacePrepRulesStatus',saved and 'Rivals moderation saved; refresh challenges.' or 'Rivals moderation refused or not saved.')
end
MP.RegisterEvent('RacePrepRivalsModerate','RacePrepRivalsModerate')
MP.RegisterEvent('RacePrepRivalsPoll','RacePrepRivalsPoll')
if features.position.available() then MP.CreateEventTimer('RacePrepRivalsPoll',50) end
MP.RegisterEvent('onVehicleReset','RacePrepRivalsReset')
MP.RegisterEvent('onVehicleEdited','RacePrepRivalsEdited')
MP.RegisterEvent('onVehicleDeleted','RacePrepRivalsDeleted')
MP.RegisterEvent('RacePrepRivals','RacePrepRivals')
MP.RegisterEvent('onPlayerDisconnect','RacePrepRivalsDisconnect')
local sharedTunes=dofile(pluginPath..'/SharedTunes.lua').new{
 now=os.time,identity=skillKey,name=MP.GetPlayerName,car=currentRatedCar,copy=Persistence.copy,
 read=function() return readJson(pluginPath..'/shared-tunes.json') end,
 exists=function() return FS.Exists(pluginPath..'/shared-tunes.json') end,
 write=function(value) return Persistence.write(pluginPath..'/shared-tunes.json',value) end,
 send=function(pid,event,p) MP.TriggerClientEvent(pid,event,Util.JsonEncode(p)) end,
}
function RacePrepSharedTunes(pid,wire)
 if not host.enabled or not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>250000 then return end
 local ok,p=pcall(Util.JsonDecode,wire);if ok then sharedTunes.handle(pid,p) end
end
function RacePrepSharedDisconnect(pid) sharedTunes.disconnect(pid);features.progress.disconnect(pid) end
MP.RegisterEvent('RacePrepSharedTunes','RacePrepSharedTunes')
MP.RegisterEvent('onPlayerDisconnect','RacePrepSharedDisconnect')
function RacePrepProgressAction(pid,wire)
 if not MP.GetPlayerName(pid) or type(wire)~='string' or #wire>2048 then return end
 local ok,p=pcall(Util.JsonDecode,wire);if not ok or type(p)~='table' then return end
 features.progressRequests=features.progressRequests or {};local now=os.time()
 local last=features.progressRequests[pid];if not last or last.at~=now then last={at=now,count=0};features.progressRequests[pid]=last end
 last.count=last.count+1;if last.count>8 then return end
 local id=rivalsDriver(pid);local saved,why
 if not id or features.progress.broken() then MP.TriggerClientEvent(pid,'RacePrepRulesStatus','Progression data unavailable; ask staff to restore it.');return end
 if not features.progress.driver(id) then local key=skillKey(pid);features.progress.refresh(id,MP.GetPlayerName(pid),raceControl.driverProfile(key),features.rating.score((skills.players[key] or {}).rating or Skill.START)) end
 if p.action=='title' then saved=features.progress.pick(id,p.title)
 elseif p.action=='card' and type(p.driver)=='string' and #p.driver<=128 and features.progress.driver(p.driver) then
  local card=features.progress.view(p.driver);card.crew=features.league.crew(p.driver)
  card.stats=features.progress.stats(p.driver)
  local league=features.league.view(id,nil,false);card.seasonRanks={}
  for _,row in ipairs(league.current and league.current.tables.drivers or {}) do if row.id==p.driver then card.seasonRanks[#card.seasonRanks+1]=row end end
  MP.TriggerClientEvent(pid,'RacePrepDriverCard',Util.JsonEncode(card));return
 elseif p.action=='history' then
  features.progressPages=features.progressPages or {};features.progressPages[pid]=math.max(1,math.min(10000,math.floor(tonumber(p.page) or 1)))
  MP.TriggerClientEvent(pid,'RacePrepLeague',Util.JsonEncode(features.league.view(id,features.progressPages[pid])));return
 elseif p.area=='season' then
  if raceControl.pendingRecords() then MP.TriggerClientEvent(pid,'RacePrepRulesStatus','Wait for pending race results to finish saving.');return end
  features.progress.flush();if features.progress.pending() then MP.TriggerClientEvent(pid,'RacePrepRulesStatus','Wait for pending progression results to finish saving.');return end
  saved,why=features.league.action(id,p,allowedTo(pid,'rules'))
 else saved,why=features.league.action(id,p,allowedTo(pid,'manageCrews')) end
 if saved then RacePrepProgressJoin(pid) end
 MP.TriggerClientEvent(pid,'RacePrepRulesStatus',saved and 'Progression change saved; refresh to see the latest state.' or why or 'Progression action refused or not saved.')
end
MP.RegisterEvent('RacePrepProgressAction','RacePrepProgressAction')
do
 local profiles=readJson(pluginPath..'/drivers.json')
 if not profiles and FS.Exists(pluginPath..'/drivers.json') then features.progress.suspend();log('Progression stopped: driver data unreadable; restore backup.') end
 profiles=profiles or {drivers={}}
 if type(profiles)=='table' and type(profiles.drivers)=='table' and not (features.progress.data().backfill or {}).done then
  local listed,found=pcall(FS.ListFiles,historyDir)
  if FS.Exists(historyDir) and not listed then features.progress.suspend();log('Progression stopped: history listing unavailable.') end
  local files={};for _,f in pairs(listed and found or {}) do if f:match('%.json$') then files[#files+1]=f end end
  table.sort(files);local results={}
  for i=math.max(1,#files-999),#files do local file=files[i];local r=readJson(file:find('/') and file or historyDir..'/'..file);if type(r)=='table' then results[#results+1]=r end end
  local weeklies=(readJson(pluginPath..'/weekly-rivals.json') or {}).picks or {}
  features.progress.backfill({profiles=profiles,skills=skills,results=results,weeklies=weeklies,score=function(e) return features.rating.score(e and e.rating or Skill.START) end},function(raw) return Skill.hash(skills.salt,raw) end)
  local b=features.progress.data().backfill
  if b then log('Progression backfill: '..b.driversRead..' drivers, '..b.resultsRead..' results, '..b.trustedResults..' trusted race results.') end
 end
end
-- BJR's plugin API (BJR 1.11+): grid order and results without touching BJR
bjrApi=dofile(pluginPath..'/BJRApi.lua').start({path=pluginPath,log=log,warn=logWarn,
 observation=function(name,d)
  if name=='RaceClosed' then features.awards.clear(d and d.sessionId) else features.awards.event(name,d) end
 end,
 eligibility=function(q,hook)
  if type(q)~='table' or type(q.session)~='table' then return end
  local r=raceRules(q.session.raceId,q.session.sessionId);local racer=q.racer or q.player or {};local pid=tonumber(racer.id)
  local identity=(host.racerIdentities[tostring(q.session.sessionId)] or {})[tostring(racer.racerKey)] or (pid and skillKey(pid))
  local licenceWhy=features.progress.refusal(r.minLicence,identity and Skill.hash(skills.salt,identity))
  if licenceWhy then return licenceWhy end
  local why=features.rating.refusal(r,identity and skills.players[identity],raceControl and raceControl.driverProfile(identity))
  if why then return why end
  if hook=='raceReady' then
   local car=(host.gridRatings[tostring(q.session.sessionId)] or {})['racer:'..tostring(racer.racerKey)] or (host.gridRatings[tostring(q.session.sessionId)] or {})[tostring(pid)]
   if not car then return 'Waiting for your current grid-car rating; try Ready again.' end
   local class=RatingStore.classOf(car.pi)
   if r.targetClass and r.targetClass~=''then
    local refusal=ClassBuild.refusal(r,car,features.factoryRating(car),RatingStore.classOf)
    if refusal then return refusal end
   end
   if r.allowedClasses and r.allowedClasses[class]==false then return 'Class '..class..' is not allowed.' end
   if r.piMin and car.pi<r.piMin then return 'PI is below the race minimum.' end
   if r.piMax and car.pi>r.piMax then return 'PI is above the race maximum.' end
  end
  if hook=='raceReady' and r.specModel and r.specModel~='' then
   if not features.catalogue.has(r.specModel) then return 'This series car is no longer available; ask staff to choose another preset.' end
   local fitted=(host.gridRatings[tostring(q.session.sessionId)] or {})['racer:'..tostring(racer.racerKey)] or (host.gridRatings[tostring(q.session.sessionId)] or {})[tostring(pid)]
   if not fitted then return 'Waiting for your current grid-car rating; try Ready again.' end
   if fitted.model~=r.specModel then return 'This series requires '..r.specModel..'.' end
   if r.specConfig and r.specConfig~='' and fitted.config~=r.specConfig then return 'This series requires configuration '..r.specConfig..'.' end
  end
 end,
 weekendDefaults=function() return motorsport.weekend end,
 gridOrder=function(raceID,qualifying,racers,bjrSession) return (gridOrderFor(raceID,host.level,qualifying,racers,bjrSession)) end,
 phaseCuts=function(sessionId,phaseIndex) return host.phaseCuts(sessionId,phaseIndex) end,
 result=function(res) local ok,err=pcall(nativeResult,res,true);if not ok then log('BJR API result: '..tostring(err)) end end,
 phaseChanged=function(d,state)
  if not weekend then weekend=Weekend.fromSession(d,os.time()) end
  -- classic: a lobby opened for this track during practice/qualifying is not the weekend's race yet
  if weekend and weekend.mode=='classic' and (weekend.stage=='practice' or weekend.stage=='qualifying') then return end
  if Weekend.update(weekend,d,state) then broadcastSession() end
 end,
 closed=function(d)
  if d then features.presets.close(d.sessionId);for player in pairs(MP.GetPlayers() or {}) do RacePrepGetPresets(player) end end
  if weekend and d and tostring(weekend.sessionId)==tostring(d.sessionId) then weekend=nil;nativePhaseView=nil;broadcastSession() end
 end,
 phaseFinished=function(d)
  if d.phase and tostring(d.phase.name):lower()=='qualifying' then
   local q=dofile(pluginPath..'/BJRApi.lua').qualifyingView({d},function() return host.phaseCuts(d.sessionId,d.phaseIndex) end);local first=q and q.rows and q.rows[1]
   if first and first.best and first.best>0 then features.qualifyingPole=features.qualifyingPole or {};features.qualifyingPole[tostring(d.sessionId)]=first.racerKey end
  end
  local follows=weekend and tostring(d.sessionId)==tostring(weekend.sessionId)
  local phase=d.phase or {};local kind=tostring(phase.name or ''):lower()
  local view=Weekend.phaseView(d,os.time()*1000)
  if view then savePhase(view) end
  if not follows then return end
  nativePhaseView=view
  weekend.results=weekend.results or {};weekend.results[kind]=view
  if kind=='qualifying' then lastQuali[weekend.raceID]={view=view,at=os.time()} end
  if d.nextPhase then Weekend.update(weekend,{raceId=d.raceId,sessionId=d.sessionId,phaseIndex=(d.phaseIndex or 0)+1,phase=d.nextPhase,phaseCount=weekend.phaseCount},'break') end
  broadcastSession()
 end,
 ready=function(info)
  features.awards.capabilities(info)
  gridPatch=true;railPage=true;MP.TriggerClientEvent(-1,'RacePrepRail','on')
  host.setLevel(info and info.map and info.map.name or host.level)
  weatherLevel=nil;syncWeather()
 end,
 mapChanged=function(d) features.awards.reset();host.setLevel(d and d.to);syncWeather() end,
 environmentChanged=function(w,by) if raceControl and raceControl.weatherFromBJR then raceControl.weatherFromBJR(host.level,w,by) end end,
 racesChanged=function() host.racesLevel=nil end,
 -- BJR menu rail page (BJRApi.pageBlocks): the player's cars, class and PI
 cars=function(pid)
  local out={}
  for _,key in pairs(ratingVehicles[tostring(pid)] or {}) do
   local e=displayRating(key)
   if e then out[#out+1]={name=e.carName or tostring(e.model):gsub('_',' '),class=e.class,pi=e.pi} end
  end
  table.sort(out,function(a,b) return a.name<b.name end)
  return out
 end,
 staff=function(pid) return canEdit(pid)==true end,
 countdown=function(d)
  if d.phase and d.phase.name=='Race' and d.grid and d.grid[1] then features.racePole=features.racePole or {};features.racePole[tostring(d.sessionId)]=d.grid[1].racerKey end
  if weekend and weekend.mode=='classic' and weekend.stage~='grid' and weekend.stage~='race' then return end
  if Weekend.update(weekend,d,'race') then broadcastSession() else weekendRaceStarted(d.raceId) end end,
 open=function(pid,section) MP.TriggerClientEvent(pid,'RacePrepOpen',section) end})
-- a client asks whether BJR's rail shows the Motorsport page (then its own
-- floating launch button is hidden)
function RacePrepRailAsk(playerID)
 if railPage and type(playerID)=='number' then MP.TriggerClientEvent(playerID,'RacePrepRail','on') end
end
MP.RegisterEvent('RacePrepRailAsk','RacePrepRailAsk')

-- Startup report, like BeamJoy's "loaded" line
do
    local function count(t) local n=0 for _ in pairs(type(t)=="table" and t or {}) do n=n+1 end return n end
    local store=readJson(pluginPath .. "/championships.json") or {}
    local champ
    for _,c in ipairs(type(store.series)=="table" and store.series or {}) do if c.id==store.active then champ=c end end
    local series=champ and string.format("%s (%s)", tostring(champ.name), tostring(champ.status)) or "none"
    if host.enabled then
        drawArt()
        logInfo(string.format("BJR:ME loaded (v%s, build %s)", RELEASE, BUILD))
        logInfo(string.format("BJR:ME: %d car ratings, rules for %d races, %d drivers rated, championship: %s",
            count(ratings and ratings.entries), count(rules.races), count(skills.players), series))
        if VERSION == "dev" then logWarn("host.json has no version: running from source, not a build") end
        for _, line in ipairs(releaseUpdates.reminders()) do logWarn(line) end
    else
        log(string.format("BJR:ME loaded: %d car ratings, rules for %d races, %d drivers rated", count(ratings and ratings.entries), count(rules.races), count(skills.players)))
    end
end
