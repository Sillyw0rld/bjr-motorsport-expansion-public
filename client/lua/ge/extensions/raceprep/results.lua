-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- Race results for the RacePrep add-on: collects every driver's checkpoint
-- times during a BeamJoy multiplayer race and builds the results when the
-- race finishes (BeamJoy clears its own race data shortly after).
--
-- Source: each leaderboard update carries a driver's lap, checkpoint and race
-- time at that checkpoint (lb.time, ms). Every crossing seen is kept, so lap
-- times and sector times come from the race times at the checkpoints.
-- Sectors: the lap's checkpoints split in three by count (S1 ends at the
-- checkpoint nearest one third of the lap, S2 at two thirds).
--
-- Track limits (rule trackLimits): every driver's cuts arrive through the
-- server (R.onCut). A lap with a cut is invalid: shown, but not a best lap.
-- With "penalty", each cut after the first cutPenaltyAfter adds
-- cutPenaltySeconds to the driver's total time, and finishers are re-sorted.
--
-- Driven from bjiRacePrep.onUpdate; the RaceResults window shows R.last.

local R = {}

R.last = nil      -- finished results (kept after BeamJoy clears the race)
R.visible = false -- RaceResults window shown
R.history = {}    -- results of this session, newest first

local run = nil
local UPDATE_S = 0.1
local nextUpdate = 0

local function getRace()
    local scenario = Platform.get("BJI_Scenario")
    if not scenario or not scenario.TYPES or not scenario.TYPES.RACE_MULTI then
        return nil
    end
    local race = scenario.get(scenario.TYPES.RACE_MULTI)
    if race and race.state and race.STATES and race.state >= race.STATES.RACE and race.race then
        return race
    end
end

local function playerName(pid)
    local ctx = Platform.get("BJI_Context")
    local p = ctx and ctx.Players and ctx.Players[pid]
    return p and p.playerName or ("Player " .. tostring(pid))
end

-- model of each driver's race car (their current vehicle)
local function carModels()
    local out = {}
    local ctx = Platform.get("BJI_Context")
    local players = ctx and ctx.Players or {}
    if not MPVehicleGE or not MPVehicleGE.getVehicles then
        return out
    end
    for _, v in pairs(MPVehicleGE.getVehicles() or {}) do
        if v.ownerID and v.jbeam then
            local current = players[v.ownerID] and players[v.ownerID].currentVehicle
            local id = v.isLocal and v.gameVehicleID or v.remoteVehID
            if (current ~= nil and id == current) or not out[v.ownerID] then
                out[v.ownerID] = v.jbeam
            end
        end
    end
    return out
end

local function modelLabel(model)
    local veh = Platform.get("BJI_Veh")
    local label = veh and veh.getModelLabel and veh.getModelLabel(model)
    return label or model
end

local function newRun(race)
    local wpPerLap = race.race.raceData and race.race.raceData.wpPerLap or
        (race.race.raceData and race.race.raceData.steps and #race.race.raceData.steps) or 1
    return {
        key = tostring(race.raceID) .. ":" .. tostring(race.race.startTime),
        raceID = race.raceID,
        raceName = race.raceName,
        raceHash = race.raceHash,
        laps = race.settings and race.settings.laps or 1,
        wpPerLap = wpPerLap,
        crossings = {}, -- pid -> step -> ms
        names = {},
        cars = {},
        order = {},
        finished = {},
        eliminated = {},
        falseStarts = {},
        cuts = {}, -- pid -> lap -> count
        finalized = false,
    }
end

--- a track-limits cut by a driver (relayed by the server)
R.onCut = function(playerID, raceID, lap)
    if not run or run.finalized or tostring(run.raceID) ~= tostring(raceID) then
        return
    end
    local pid = tonumber(playerID) or playerID
    lap = math.max(1, math.floor(tonumber(lap) or 1))
    run.cuts[pid] = run.cuts[pid] or {}
    run.cuts[pid][lap] = (run.cuts[pid][lap] or 0) + 1
end

R.onControl = function(state)
    local race=getRace()
    local current=race and tostring(race.raceID)..':'..tostring(race.race.startTime)
    if run and current==run.key and state.runID and tostring(run.raceID)==tostring(state.raceID) then
        run.runID=state.runID
        run.falseStarts=state.falseStarts or {}
    end
end

local function trackRules(raceID)
    local rt = rawget(_G, "bjiRacePrep")
    local rules = rt and rt.getRules and rt.getRules(raceID) or {}
    return rules.trackLimits or "invalid", math.max(0, tonumber(rules.cutPenaltyAfter) or 3),
        math.max(0, tonumber(rules.cutPenaltySeconds) or 5)
end

local function capture(r, race)
    local cars = carModels()
    local order = {}
    for _, lb in ipairs(race.race.leaderboard or {}) do
        local pid = lb.playerID
        table.insert(order, pid)
        r.names[pid] = playerName(pid)
        r.cars[pid] = cars[pid] or r.cars[pid]
        local t = tonumber(lb.time)
        local step = (math.max(lb.lap or 1, 1) - 1) * r.wpPerLap + math.max(lb.wp or 0, 0)
        if t and step > 0 and not lb.desync then
            r.crossings[pid] = r.crossings[pid] or {}
            if r.crossings[pid][step] == nil then
                r.crossings[pid][step] = t
            end
        end
    end
    if #order > 0 then
        r.order = order
    end
    for _, pid in ipairs(race.race.finished or {}) do r.finished[pid] = true end
    for _, pid in ipairs(race.race.eliminated or {}) do r.eliminated[pid] = true end
end

local function sectorBounds(wpPerLap)
    if wpPerLap < 3 then
        return nil
    end
    local b1 = math.max(1, math.floor(wpPerLap / 3 + 0.5))
    local b2 = math.max(b1 + 1, math.floor(2 * wpPerLap / 3 + 0.5))
    if b2 >= wpPerLap then
        return nil
    end
    return { b1, b2 }
end

local function lapBreakdown(c, wpPerLap, lap, bounds)
    local base = (lap - 1) * wpPerLap
    local t0 = lap == 1 and 0 or c[base]
    local t1 = c[base + wpPerLap]
    if not t0 or not t1 then
        return nil
    end
    local lapData = { lap = lap, time = t1 - t0 }
    if bounds then
        local a, b = c[base + bounds[1]], c[base + bounds[2]]
        if a and b then
            lapData.sectors = { a - t0, b - a, t1 - b }
        end
    end
    return lapData
end

local function finalize(r)
    r.finalized = true
    local bounds = sectorBounds(r.wpPerLap)
    local limits, penaltyAfter, penaltySeconds = trackRules(r.raceID)
    local rows = {}
    for _, pid in ipairs(r.order) do
        local c = r.crossings[pid] or {}
        local cuts = limits ~= "off" and (r.cuts or {})[pid] or {}
        local maxStep = 0
        for step in pairs(c) do maxStep = math.max(maxStep, step) end
        local lapsDone = math.min(math.floor(maxStep / r.wpPerLap), r.laps)
        local row = {
            playerID = pid,
            name = r.names[pid],
            car = r.cars[pid] and modelLabel(r.cars[pid]) or "?",
            model = r.cars[pid],
            laps = lapsDone,
            steps = maxStep,
            lastTime = c[maxStep],
            lapList = {},
        }
        local finished = r.finished[pid] and lapsDone >= r.laps
        row.status = finished and "FIN" or (r.eliminated[pid] and "DNF" or "DNF")
        row.total = finished and c[r.laps * r.wpPerLap] or nil
        row.cuts = 0
        for _, n in pairs(cuts) do row.cuts = row.cuts + n end
        if limits == "penalty" and row.cuts > penaltyAfter then
            row.penalty = (row.cuts - penaltyAfter) * penaltySeconds * 1000
            if row.total then row.total = row.total + row.penalty end
        end
        row.falseStartPenalty = (r.falseStarts or {})[tostring(pid)]
        if row.falseStartPenalty then
            row.falseStart=true
            row.penalty=(row.penalty or 0)+row.falseStartPenalty
            if row.total then row.total=row.total+row.falseStartPenalty end
        end
        local bestSectors = {}
        for lap = 1, lapsDone do
            local l = lapBreakdown(c, r.wpPerLap, lap, bounds)
            if l then
                l.cuts = cuts[lap]
                l.invalid = cuts[lap] ~= nil or nil
                table.insert(row.lapList, l)
                if not l.invalid and (not row.best or l.time < row.best.time) then
                    row.best = l
                end
                -- fastest lap including cut laps (results show it red when invalid)
                if not row.bestAny or l.time < row.bestAny.time then
                    row.bestAny = l
                end
                for i, s in ipairs(not l.invalid and l.sectors or {}) do
                    if not bestSectors[i] or s < bestSectors[i] then bestSectors[i] = s end
                end
            end
        end
        if bounds and #bestSectors == 3 then
            row.bestSectors = bestSectors
            row.theoretical = bestSectors[1] + bestSectors[2] + bestSectors[3]
        end
        table.insert(rows, row)
    end
    -- finishers by total time, then the rest by distance covered and time
    table.sort(rows, function(a, b)
        if a.total and b.total then return a.total < b.total end
        if a.total or b.total then return a.total ~= nil end
        if a.steps ~= b.steps then return a.steps > b.steps end
        return (a.lastTime or math.huge) < (b.lastTime or math.huge)
    end)
    local winner = rows[1]
    local fastest
    for i, row in ipairs(rows) do
        row.position = i
        if row.total and winner and winner.total then
            row.gap = row.total - winner.total
        elseif winner and i > 1 then
            row.lapsDown = math.max(0, (winner.laps or 0) - (row.laps or 0))
        end
        if row.best and (not fastest or row.best.time < fastest.best.time) then
            fastest = row
        end
    end
    if fastest then
        fastest.fastestLap = true
    end
    local results = {
        key = r.key,
        runID = r.runID,
        raceID = r.raceID,
        raceName = r.raceName,
        raceHash = r.raceHash,
        laps = r.laps,
        checkpointsPerLap = r.wpPerLap,
        sectorBounds = bounds,
        date = os.date("%Y-%m-%d %H:%M:%S"),
        rows = rows,
    }
    R.last = results
    R.visible = true
    table.insert(R.history, 1, results)
    while #R.history > 10 do
        table.remove(R.history)
    end
    if type(rawget(_G, "TriggerServerEvent")) == "function" then
        local ok, json = pcall(jsonEncode, results)
        if ok then
            require('ge/extensions/raceprep/net').send("RacePrepRaceResult", json)
        end
    end
end
R.finalizeForTest = finalize

--- called every frame by bjiRacePrep with its clock (s)
R.update = function(clock)
    if clock < nextUpdate then
        return
    end
    nextUpdate = clock + UPDATE_S
    local race = getRace()
    if not race then
        if run and not run.finalized and next(run.crossings) then
            finalize(run) -- the race was cleared before its finish state
        end
        run = nil
        return
    end
    local key = tostring(race.raceID) .. ":" .. tostring(race.race.startTime)
    if not run or run.key ~= key then
        if run and not run.finalized and next(run.crossings) then
            finalize(run)
        end
        run = newRun(race)
    end
    if run.finalized then
        return
    end
    capture(run, race)
    if race.state == race.STATES.FINISHED then
        finalize(run)
    end
end

R.formatTime = function(ms)
    if not ms then
        return "--"
    end
    local total = ms / 1000
    local m = math.floor(total / 60)
    return string.format("%d:%06.3f", m, total - m * 60)
end

return R
