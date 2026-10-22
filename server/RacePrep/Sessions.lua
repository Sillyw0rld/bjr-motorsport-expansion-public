-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Practice and qualifying sessions for the RacePrep server plugin.
--
-- A session runs in free roam on a BeamJoy race's track: each driver's game
-- times its own laps (raceprep/lapTracker) and sends them here; this module
-- keeps the standings and decides when the session is over. A lap counts if
-- it was started before the clock ran out, so drivers on a lap at zero may
-- finish it (grace: up to 1.5 x the session's best lap, max 3 minutes).
--
-- Grid order for the race that follows (rule gridOrder):
--   "join"       BeamJoy's own order (who joined first starts first)
--   "qualifying" best valid qualifying lap first; drivers without a valid
--                lap after them
--   "reverse"    qualifying order with the top N reversed (gridReverseTop)
--   "handicap"   slowest car (lowest PI) first
-- The order is handed to BeamJoy's race manager by the BeamJoyCore patch
-- (RacePrepGridOrder event); drivers it does not list keep their join order
-- behind the listed ones.
--
-- Plain Lua 5.1 (no BeamMP API), so it runs in tests too.

local S = {}

S.TYPES = { practice = "Practice", qualifying = "Qualifying" }
S.GRACE_MAX_S = 180

S.new = function(id, raceID, raceName, kind, minutes, now)
    return {
        id = id,
        raceID = tostring(raceID),
        raceName = raceName,
        type = kind,
        minutes = minutes,
        startedAt = now,
        endsAt = now + minutes * 60,
        state = "running", -- running | overtime | ended
        drivers = {},      -- key -> {playerID, name, best, bestLap, laps, valid, model, pi, lastAt}
        order = 0,
    }
end

-- Missing/malformed splits do not invent sectors or invalidate a timed lap.
local function sectorTimes(values, total, variable)
    if type(values) ~= "table" or #values < 1 or #values > 64 or (not variable and #values ~= 3) then return nil end
    local sectors, sum = {}, 0
    for i = 1, #values do
        local value = tonumber(values[i])
        if not value or value ~= value or value <= 0 or value > total then return nil end
        sectors[i] = math.floor(value + 0.5)
        sum = sum + sectors[i]
    end
    if math.abs(sum - total) > 2 then return nil end
    sectors[#values] = sectors[#values] + total - sum
    if sectors[#values] <= 0 then return nil end
    return sectors
end

--- record a lap. lap: {time (ms), valid, cuts, startedAt (s, server time
--- estimate), model, pi}. Returns the driver entry, or nil if refused.
S.addLap = function(s, playerID, name, lap, now)
    if s.state == "ended" or type(lap) ~= "table" then
        return nil
    end
    local time = tonumber(lap.time)
    if not time or time ~= time or time < 10000 or time > 3600000 then
        return nil
    end
    -- laps finishing after zero count only if they started before it
    if (s.overtimeEnd and now >= s.overtimeEnd) or
        (now >= s.endsAt and (lap.beforeEnd ~= true or now - time / 1000 >= s.endsAt)) then
        return nil
    end
    local key = tostring(playerID)
    local d = s.drivers[key]
    if not d then
        s.order = s.order + 1
        d = { playerID = playerID, name = name, laps = 0, valid = 0, order = s.order }
        s.drivers[key] = d
    end
    d.name = name or d.name
    d.laps = d.laps + 1
    d.lastAt = now
    local sectors = sectorTimes(lap.sectors, time, s.variableSectors)
    d.last = { time = time, valid = lap.valid == true, cuts = tonumber(lap.cuts) or 0, sectors = sectors }
    if lap.valid == true then
        d.valid = d.valid + 1
        if not d.best or time < d.best then
            d.best = time
            d.bestLap = d.laps
            d.bestSectors = sectors
            d.model = lap.model
            d.pi = tonumber(lap.pi)
            d.class = lap.class
        end
    end
    return d
end

--- drivers sorted: best valid lap first, then those without one (by first lap)
S.standings = function(s)
    local list = {}
    for _, d in pairs(s.drivers) do table.insert(list, d) end
    table.sort(list, function(a, b)
        if a.best and b.best then
            if a.best ~= b.best then return a.best < b.best end
            return a.order < b.order
        end
        if a.best or b.best then return a.best ~= nil end
        return a.order < b.order
    end)
    return list
end

local function bestOverall(s)
    local best
    for _, d in pairs(s.drivers) do
        if d.best and (not best or d.best < best) then best = d.best end
    end
    return best
end

--- advance the session clock; returns "overtime" or "ended" when it changes
S.tick = function(s, now)
    if s.state == "running" and now >= s.endsAt then
        s.state = "overtime"
        local best = bestOverall(s)
        s.overtimeEnd = s.endsAt + math.min(S.GRACE_MAX_S, best and best / 1000 * 1.5 or S.GRACE_MAX_S)
        return "overtime"
    end
    if s.state == "overtime" and now >= s.overtimeEnd then
        s.state = "ended"
        return "ended"
    end
end

--- what clients get (no internal fields)
S.view = function(s, now)
    local rows = {}
    local leader
    for i, d in ipairs(S.standings(s)) do
        leader = leader or d.best
        table.insert(rows, {
            pos = i, playerID = d.playerID, name = d.name, best = d.best, bestLap = d.bestLap, bestSectors = d.bestSectors, laps = d.laps,
            gap = (d.best and leader and i > 1) and (d.best - leader) or nil,
            model = d.model, pi = d.pi, class = d.class, last = d.last,
        })
    end
    return {
        id = s.id, level = s.level, raceID = s.raceID, raceName = s.raceName, type = s.type, label = S.TYPES[s.type],
        state = s.state, minutes = s.minutes,
        deadlineRemaining = math.floor((s.endsAt - now) * 1000),
        remaining = math.max(0, math.floor((s.endsAt - now) * 1000)),
        overtimeRemaining = s.overtimeEnd and math.max(0, math.floor((s.overtimeEnd - now) * 1000)) or nil,
        rows = rows,
    }
end

--- grid order: list of {playerID, name}; nil = leave BeamJoy's join order
--- mode: rules.gridOrder; quali: the race's last qualifying view (or nil);
--- cars: { [playerID] = pi } reported from the grid
S.gridOrder = function(mode, quali, cars, reverseTop)
    if mode == "handicap" then
        local list = {}
        for pid, pi in pairs(cars or {}) do
            pi = tonumber(pi)
            if pi and pi == pi and pi > 0 and pi < math.huge then
                table.insert(list, { playerID = tonumber(pid) or pid, pi = pi })
            end
        end
        if #list == 0 then return nil end
        table.sort(list, function(a, b)
            if a.pi ~= b.pi then return a.pi < b.pi end
            return tostring(a.playerID) < tostring(b.playerID)
        end)
        return list
    end
    if (mode == "qualifying" or mode == "reverse") and quali and type(quali.rows) == "table" then
        local list = {}
        for _, r in ipairs(quali.rows) do
            table.insert(list, { playerID = r.playerID, name = r.name, valid = r.best ~= nil })
        end
        if mode == "reverse" then
            local n = 0
            for _, r in ipairs(list) do if r.valid then n = n + 1 end end
            n = math.min(n, math.max(0, math.floor(tonumber(reverseTop) or 0)))
            for i = 1, math.floor(n / 2) do
                list[i], list[n + 1 - i] = list[n + 1 - i], list[i]
            end
        end
        return #list > 0 and list or nil
    end
    return nil
end

return S
