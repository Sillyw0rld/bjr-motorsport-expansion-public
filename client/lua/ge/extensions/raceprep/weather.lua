-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race Prep weather (cloud cover, fog, rain, air temperature) per map, set by
-- admins in the Track settings and decided by the server, so every player
-- races in the same conditions. Track temperature (built-in roadTemperature) and
-- KTS tyre heat follow air temperature, clouds and rain, so they match too.
--
-- Ownership, field by field: when BeamJoy (BJR weather sync, or the original
-- BeamJoy's weather control) already syncs a field, Race Prep leaves it alone
-- and reports "BeamJoy". Race Prep controls only what nobody else syncs, and
-- puts the map's own values back when it lets go (setting off, BeamJoy takes
-- over, map change or leaving the server).
--
-- Air temperature: BeamNG keeps a cached copy of the level's temperature curve
-- and only re-reads it when the level is flagged as edited. Setting the curve
-- alone has no effect (tested in 0.39: stayed at 15 C), so the level is flagged
-- for one update, then the flag is cleared again. Vehicles (obj:getEnvTemperature,
-- read by KTS) follow within a frame.
local W = {}

W.FIELDS = {
    cloud = { bjr = { "cloudCover" } },
    fog = { bjr = { "fogDensity", "fogAtmosphereHeight" } },
    rain = { bjr = { "numOfDrops", "rainDrops", "rain", "precipitation" } },
    -- BJR 2.0 syncs the day's temperature as temperatureCurveOverrideC (BJR:ME's
    -- server sends its track preset there when BJR's weather sync is on)
    temperature = { bjr = { "temperatureCurveOverrideC", "tempCurve", "temperatureCurve", "temperature", "temperatureK" } },
}
W.status = {}

local baseline = {}      -- field -> map value before Race Prep changed it
local baselineLevel = nil
local clearDirty = nil   -- LevelInfo flagged by us, to clear on the next update
local lastCheck = -1e9

local function finite(v, lo, hi)
    v = tonumber(v)
    return v and v == v and v >= lo and v <= hi and v or nil
end

local function levelInfo()
    local names = scenetree and scenetree.findClassObjects and scenetree.findClassObjects("LevelInfo")
    return names and names[1] and scenetree.findObject(names[1]) or nil
end

--- which weather fields BeamJoy syncs right now (BJR data.weather keys, or
--- the original BeamJoy's controlWeather); nil = none
W.beamJoyOwns = function(field)
    local keys = W.FIELDS[field] and W.FIELDS[field].bjr or {}
    local bjr = rawget(_G, "beamjoy_environment")
    local d = bjr and bjr.data
    if type(d) == "table" and d.weatherSync and type(d.weather) == "table" then
        for _, k in ipairs(keys) do
            if d.weather[k] ~= nil then return true end
        end
    end
    local bji = rawget(_G, "BJI_Env")
    if type(bji) == "table" and type(bji.Data) == "table" and bji.Data.controlWeather then return true end
    return false
end

-- desired curve: BeamNG time of day 0 = noon, .25 = dusk, .5 = midnight, .75 = dawn
local function curveOf(w)
    return { { 0, w.tempNoon }, { 0.25, w.tempDusk }, { 0.5, w.tempMidnight }, { 0.75, w.tempDawn }, { 1, w.tempNoon } }
end

local function sameCurve(a, b)
    if type(a) ~= "table" or #a ~= #b then return false end
    for i = 1, #b do
        if not a[i] or math.abs((a[i][1] or -1) - b[i][1]) > 1e-3 or math.abs((a[i][2] or -999) - b[i][2]) > 0.05 then return false end
    end
    return true
end

local function copyCurve(c)
    local out = {}
    for i, p in ipairs(c or {}) do out[i] = { p[1], p[2] } end
    return out
end

local function setCurve(li, curve)
    local wasDirty = li.isEditorDirty and li:isEditorDirty()
    li:setTemperatureCurveC(curve)
    if li.setEditorDirty and not wasDirty then
        li:setEditorDirty(true)
        clearDirty = li
    end
end

-- readers / writers per field
local IO = {
    cloud = {
        get = function() return core_environment.getCloudCover and core_environment.getCloudCover() end,
        set = function(v) core_environment.setCloudCover(v) end,
        want = function(w) return finite(w.cloudCover, 0, 2) end,
        same = function(a, b) return math.abs(a - b) < 1e-3 end,
    },
    fog = {
        get = function() return core_environment.getFogDensity and core_environment.getFogDensity() end,
        set = function(v) core_environment.setFogDensity(v) end,
        want = function(w) return finite(w.fogDensity, 0, 0.05) end,
        same = function(a, b) return math.abs(a - b) < 1e-6 end,
    },
    rain = {
        get = function() return core_environment.getPrecipitation and core_environment.getPrecipitation() end,
        set = function(v) core_environment.setPrecipitation(v) end,
        want = function(w) local v = finite(w.rainDrops, 0, 5000); return v and math.floor(v + 0.5) end,
        same = function(a, b) return math.abs(a - b) < 0.5 end,
    },
    temperature = {
        get = function() local li = levelInfo(); return li and li.getTemperatureCurveC and copyCurve(li:getTemperatureCurveC()) end,
        set = function(v) local li = levelInfo(); if li then setCurve(li, v) end end,
        want = function(w)
            for _, k in ipairs({ "tempNoon", "tempDusk", "tempMidnight", "tempDawn" }) do
                if not finite(w[k], -40, 60) then return nil end
            end
            return curveOf(w)
        end,
        same = function(a, b) return sameCurve(a, b) end,
    },
}

local function release(field)
    local value = baseline[field]
    baseline[field] = nil
    if value == nil or not core_environment then return end
    if baselineLevel and getCurrentLevelIdentifier and getCurrentLevelIdentifier() ~= baselineLevel then return end
    pcall(IO[field].set, value)
end

--- give every field back to the map (setting off, map change, leaving)
W.restore = function()
    for field in pairs(IO) do release(field) end
    baseline, baselineLevel = {}, nil
    if clearDirty then pcall(function() clearDirty:setEditorDirty(false) end); clearDirty = nil end
    W.status = {}
end

--- track: the server's per-map view ({level, weather = {enabled, cloudCover,
--- fogDensity, rainDrops, tempNoon, tempDusk, tempMidnight, tempDawn}})
W.update = function(track, clock)
    if clearDirty then
        -- one update with the flag set is enough for BeamNG to re-read the curve
        pcall(function() clearDirty:setEditorDirty(false) end)
        clearDirty = nil
    end
    if not core_environment then return end
    local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
    if baselineLevel and level ~= baselineLevel then
        baseline, baselineLevel = {}, nil -- new map: its own values are back anyway
    end
    local w = track and track.weather
    local active = type(w) == "table" and w.enabled == true and
        (not track.level or tostring(track.level):lower() == tostring(level or ""):lower())
    if (clock or 0) - lastCheck < 2 then return end
    lastCheck = clock or 0
    local status = {}
    for field, io in pairs(IO) do
        if W.beamJoyOwns(field) then
            -- BeamJoy syncs this one: never write it; forget our baseline
            -- (BeamJoy sets its own value, restoring ours would fight it)
            baseline[field] = nil
            status[field] = "synced through BJR"
        elseif not active then
            release(field)
            status[field] = "map default"
        else
            local ok, current = pcall(io.get)
            local want = io.want(w)
            if not ok or current == nil then
                status[field] = field == "rain" and "no rain on this map" or "not available on this map"
            elseif want == nil then
                status[field] = "map default"
            else
                if baseline[field] == nil then
                    baseline[field] = type(current) == "table" and copyCurve(current) or current
                    baselineLevel = level
                end
                if not io.same(current, want) then pcall(io.set, want) end
                status[field] = "Motorsport Expansion"
            end
        end
    end
    W.status = status
end

return W
