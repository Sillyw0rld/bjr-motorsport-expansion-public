-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Road Temperature: built into Motorsport Expansion (BJR:ME) since 2.12.0 (was
-- the separate road_temperature mod, never published; retired 2026-10-20).
--
-- Gives the track its own temperature, like racing sims do: air temperature
-- plus heating from the sun (time of day), reduced by cloud cover and rain,
-- a little below air on clear nights. The asphalt follows that target slowly
-- (heat soak), so the hottest track comes in the early afternoon.
--
-- The value reaches Kagoni Tyre Simulation (KTS), unmodified, through its own
-- "tyreWearMailboxEnvTemp" mailbox: stock KTS takes road temperature as that
-- value minus 3 C, so the track temperature + 3 is sent several times a second
-- (KTS's own script sends the plain air temperature only every 30 s and on
-- spawn, so ours is the value in use). Side effect: KTS also uses that value
-- as the air its tyres cool towards. The older "ktsRoadTempC" mailbox
-- (degrees C as text, or "off") is still sent for tyre mods that read it.
-- Without a tyre mod it is display only.
--
-- API for other mods (GE Lua):
--   roadTemperature.get()             -> { air, track, target, cloud, wet, fixed, fixedSource } or nil
--   roadTemperature.setFixed(c, src)  -- force a track temperature (nil = back to the live model)
--   roadTemperature.setOverlay(bool)  -- show/hide the Air / Track overlay
--

local M = {}

local UPDATE_S = 2
local LAG_S = 300              -- time constant of the asphalt heat soak
local MAX_SOLAR_GAIN_C = 22    -- clear sky, sun overhead
local CLOUD_BLOCK = 0.8        -- full overcast removes 80% of the solar gain
local WET_FACTOR = 0.25        -- rain keeps the surface near air temperature
local NIGHT_COOLING_C = 3      -- clear-sky radiative cooling at night
local JUMP_C = 15              -- bigger changes are applied at once, no soak
local MAILBOX = "ktsRoadTempC"
local KTS_MAILBOX = "tyreWearMailboxEnvTemp" -- stock KTS: road = value - 3 C
local KTS_ROAD_OFFSET_C = 3
local KTS_SEND_S = 0.25
local SETTINGS_FILE = "settings/roadTemperature.json"

local clock = 0
local nextUpdate = 0
local state          -- last computed values
local fixedC, fixedSource
local sentToTyres = false
local nextKts = 0
local settings = { showOverlay = true }

local function loadSettings()
    local ok, data = pcall(jsonReadFile, SETTINGS_FILE)
    if ok and type(data) == "table" and type(data.showOverlay) == "boolean" then
        settings.showOverlay = data.showOverlay
    end
end

local function saveSettings()
    pcall(jsonWriteFile, SETTINGS_FILE, settings, true)
end

local function send(value)
    if be and be.sendToMailbox then
        be:sendToMailbox(MAILBOX, value)
    end
end

--- stock KTS: track + 3 (it subtracts 3 for the road); nil hands back the real air temperature
local function sendKts(trackC)
    if not (be and be.sendToMailbox) then return end
    if trackC then
        be:sendToMailbox(KTS_MAILBOX, trackC + KTS_ROAD_OFFSET_C)
    else
        local env = rawget(_G, "core_environment")
        local airK = env and env.getTemperatureK and tonumber(env.getTemperatureK())
        if airK and airK > 0 then be:sendToMailbox(KTS_MAILBOX, airK - 273.15) end
    end
end

--- air C, sun height (1 noon .. 0 at 6:00/18:00 .. negative at night), cloud 0..1, wet
local function readEnvironment()
    local env = rawget(_G, "core_environment")
    if not env or not env.getTemperatureK then
        return nil
    end
    local airK = tonumber(env.getTemperatureK())
    if not airK or airK <= 0 then
        return nil -- no level loaded yet
    end
    local tod = env.getTimeOfDay and env.getTimeOfDay()
    local todTime = tod and tonumber(tod.time) or 0
    local cloud = env.getCloudCover and tonumber(env.getCloudCover()) or 0.3
    cloud = math.max(0, math.min(1, cloud))
    local drops = env.getPrecipitation and tonumber(env.getPrecipitation()) or 0
    -- BeamNG time of day: 0 = 12:00, 0.5 = 00:00
    local dayFraction = (todTime + 0.5) % 1
    local sun = -math.cos(2 * math.pi * dayFraction)
    return airK - 273.15, sun, cloud, drops > 0
end

local function targetTemperature(air, sun, cloud, wet)
    if sun > 0 then
        local gain = MAX_SOLAR_GAIN_C * sun ^ 1.3 * (1 - CLOUD_BLOCK * cloud)
        if wet then
            gain = gain * WET_FACTOR
        end
        return air + gain
    end
    local night = math.min(1, -sun * 3)
    return air - NIGHT_COOLING_C * night * (1 - cloud) * (wet and 0.3 or 1)
end

local function update()
    local air, sun, cloud, wet = readEnvironment()
    if not air then
        if sentToTyres then
            send("off")
            sendKts(nil)
            sentToTyres = false
        end
        state = nil
        return
    end
    local target = targetTemperature(air, sun, cloud, wet)
    local track
    if fixedC then
        track = fixedC
    elseif not state or state.fixed or math.abs(state.track - target) > JUMP_C then
        track = target
    else
        local alpha = 1 - math.exp(-(clock - state.at) / LAG_S)
        track = state.track + (target - state.track) * alpha
    end
    state = {
        air = air, track = track, target = target, cloud = cloud, wet = wet,
        fixed = fixedC ~= nil, fixedSource = fixedSource, at = clock,
    }
    send(string.format("%.2f", track))
    sentToTyres = true
end

---------------------------------------------------------------- overlay

local overlayOpen
local function drawOverlay()
    if not settings.showOverlay or not state then
        return
    end
    local im = rawget(_G, "ui_imgui")
    if not im or not getPlayerVehicle or not getPlayerVehicle(0) then
        return
    end
    overlayOpen = overlayOpen or im.BoolPtr(true)
    overlayOpen[0] = true
    local viewport = im.GetMainViewport()
    im.SetNextWindowPos(im.ImVec2(viewport.Size.x - 260, 60), im.Cond_FirstUseEver)
    local flags = im.flags(im.WindowFlags_AlwaysAutoResize, im.WindowFlags_NoCollapse,
        im.WindowFlags_NoFocusOnAppearing)
    if im.Begin("Road Temperature##roadTemperatureOverlay", overlayOpen, flags) then
        im.TextColored(im.ImVec4(0.75, 0.85, 1, 1), string.format("Air %.0f\194\176C", state.air))
        im.SameLine()
        local hot = math.max(0, math.min(1, (state.track - 15) / 35))
        im.TextColored(im.ImVec4(1, 1 - 0.55 * hot, 0.35, 1), string.format("   Track %.0f\194\176C", state.track))
        if state.fixed then
            im.TextColored(im.ImVec4(0.7, 0.7, 0.7, 1), "fixed by " .. tostring(state.fixedSource or "another mod"))
        elseif state.wet then
            im.TextColored(im.ImVec4(0.6, 0.8, 1, 1), "wet track")
        end
    end
    im.End()
    if not overlayOpen[0] then
        M.setOverlay(false)
    end
end

---------------------------------------------------------------- API

M.get = function()
    if not state then
        return nil
    end
    return {
        air = state.air, track = state.track, target = state.target, cloud = state.cloud,
        wet = state.wet, fixed = state.fixed, fixedSource = state.fixedSource,
    }
end

M.setFixed = function(celsius, source)
    celsius = tonumber(celsius)
    if celsius and (celsius ~= celsius or celsius < -50 or celsius > 90) then
        celsius = nil
    end
    local changed = celsius ~= fixedC
    fixedC = celsius
    fixedSource = celsius and source or nil
    if changed then
        nextUpdate = 0 -- apply now
    end
end

M.setOverlay = function(show)
    settings.showOverlay = show and true or false
    saveSettings()
end

---------------------------------------------------------------- hooks

M.onUpdate = function(dtReal)
    clock = clock + (tonumber(dtReal) or 0)
    if clock >= nextUpdate then
        nextUpdate = clock + UPDATE_S
        local ok, err = pcall(update)
        if not ok then
            log("E", "roadTemperature", tostring(err))
        end
    end
    if state and clock >= nextKts then
        nextKts = clock + KTS_SEND_S
        sendKts(state.track)
    end
    drawOverlay()
end

M.onVehicleSpawned = function()
    nextKts = 0 -- KTS sends the plain air temperature on spawn: replace it at once
end

M.onClientEndMission = function()
    state = nil
    if sentToTyres then
        send("off")
        sendKts(nil)
        sentToTyres = false
    end
end

M.onExtensionUnloaded = function()
    if sentToTyres then
        send("off")
        sendKts(nil)
    end
end

M.onExtensionLoaded = function()
    loadSettings()
    log("I", "roadTemperature", "Road Temperature (Motorsport Expansion) loaded")
end

return M
