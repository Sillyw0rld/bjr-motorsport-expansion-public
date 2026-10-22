-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- Race timing for the RacePrep HUD and standings tower.
--
-- Builds a snapshot (at most every SNAPSHOT_MS) from what BeamJoy already has
-- on the client:
--  * race.race.leaderboard: per driver lap / checkpoint, the race time at
--    their last checkpoint (lb.time, ms) and the gap to the leader (lb.diff)
--  * race.race.raceData.steps: checkpoint positions
--  * race.lapData + the stored personal best (per-checkpoint lap times)
--  * every car's live position (BeamMP syncs all vehicles to every client)
--
-- Gaps:
--  * interval (exact): the time between two drivers at the SAME checkpoint.
--    Every leaderboard update is remembered, so for my last checkpoint we
--    know when the car ahead crossed it too. Falls back to the difference of
--    the leader gaps when a crossing was missed.
--  * distance: each car's progress along the race path (raceprep/racePath:
--    the line actually driven, recorded by this game per race layout; a
--    straight line between checkpoints until recorded).
--  * live gap: how long ago the car ahead was where I am now (from each car's
--    progress history). Approximate, but it moves smoothly between
--    checkpoints and is right under braking and acceleration.

local T = {}

local RacePath = require("ge/extensions/raceprep/racePath")

local SNAPSHOT_MS = 50
local HISTORY_MS = 120000 -- progress history kept per car
local cache = { now = nil, builtAt = -1e9, snapshot = nil }
-- per race run: best/last lap, checkpoint crossings, progress histories
local raceMemory = nil
-- BJI_LocalStorage.get deep-copies every stored PB (all races, all maps), so
-- reading it every frame caused GC hitches; keep it per race, refresh rarely
local PB_REFRESH_MS = 5000
local pbCache = { hash = nil, at = 0, pb = nil }

local function getPB(raceHash, now)
    if not raceHash or not BJI_RaceWaypoint or not BJI_RaceWaypoint.getPB then
        return nil
    end
    if pbCache.hash ~= raceHash or now - pbCache.at > PB_REFRESH_MS then
        pbCache.hash = raceHash
        pbCache.at = now
        pbCache.pb = BJI_RaceWaypoint.getPB(raceHash)
    end
    return pbCache.pb
end

local function getRace()
    if not BJI_Scenario or not (Platform.get("BJI_Scenario") or {}).TYPES or not (Platform.get("BJI_Scenario") or {}).TYPES.RACE_MULTI then
        return nil
    end
    local race = (Platform.get("BJI_Scenario") or {}).get((Platform.get("BJI_Scenario") or {}).TYPES.RACE_MULTI)
    if race and race.state and race.STATES and race.state >= race.STATES.RACE and
        race.race and race.race.raceData and race.race.raceData.steps then
        return race
    end
end
T.getRace = getRace

local function stepPos(step)
    local wp = step and step[1]
    return wp and wp.pos
end

local function newMemory(race)
    local steps = race.race.raceData.steps
    local wpPerLap = race.race.raceData.wpPerLap or #steps
    local cps = {}
    for i = 1, wpPerLap do
        local p = stepPos(steps[i])
        cps[i] = p and { x = p.x, y = p.y, z = p.z } or nil
    end
    local grid = race.grid and race.grid.startPositions and race.grid.startPositions[1]
    local start = grid and grid.pos and { x = grid.pos.x, y = grid.pos.y, z = grid.pos.z } or cps[1]
    return {
        raceID = race.raceID,
        startTime = race.race.startTime,
        wpPerLap = wpPerLap,
        path = RacePath.new(race.raceHash, cps, start, wpPerLap),
        best = {}, last = {}, seenLapTime = {},
        crossings = {}, -- playerID -> step index -> race time (ms)
        history = {},   -- playerID -> list of {t, progress}
        ownLap = nil,
    }
end

-- each driver's race car: their current vehicle (BeamJoy context), or the
-- first spawned vehicle they own
local function raceVehicles(players)
    local out, first = {}, {}
    if not MPVehicleGE or not MPVehicleGE.getVehicles then
        return out
    end
    for _, v in pairs(MPVehicleGE.getVehicles() or {}) do
        if v.isSpawned and not v.isDeleted and v.ownerID then
            local obj = getObjectByID and getObjectByID(v.gameVehicleID)
            if obj then
                local player = players[v.ownerID]
                local current = player and player.currentVehicle
                local id = v.isLocal and v.gameVehicleID or v.remoteVehID
                if current ~= nil and id == current then
                    out[v.ownerID] = obj
                elseif not first[v.ownerID] then
                    first[v.ownerID] = obj
                end
            end
        end
    end
    for owner, obj in pairs(first) do
        out[owner] = out[owner] or obj
    end
    return out
end

local function stepIndex(lap, wp, wpPerLap)
    return (math.max(lap or 1, 1) - 1) * wpPerLap + math.max(wp or 0, 0)
end

local function rememberLeaderboard(mem, race)
    for _, lb in ipairs(race.race.leaderboard or {}) do
        local key = tostring(lb.playerID) .. ":" .. tostring(lb.lap) .. ":" .. tostring(lb.lapTime)
        if lb.lapTime and lb.lapTime > 0 and not mem.seenLapTime[key] then
            mem.seenLapTime[key] = true
            mem.last[lb.playerID] = lb.lapTime
            if not mem.best[lb.playerID] or lb.lapTime < mem.best[lb.playerID] then
                mem.best[lb.playerID] = lb.lapTime
            end
        end
        local t = tonumber(lb.time)
        local passedOne = (lb.wp or 0) > 0 or (lb.lap or 1) > 1
        if t and not lb.desync and passedOne then
            local c = mem.crossings[lb.playerID] or {}
            mem.crossings[lb.playerID] = c
            local k = stepIndex(lb.lap, lb.wp, mem.wpPerLap)
            if c[k] == nil then
                c[k] = t
            end
        end
    end
end

local function pushHistory(mem, playerID, now, progress)
    local h = mem.history[playerID] or {}
    mem.history[playerID] = h
    local lastEntry = h[#h]
    if lastEntry and progress < lastEntry.p - 50 then
        -- went backwards a lot (reset to a checkpoint): start a new history
        for i = #h, 1, -1 do h[i] = nil end
    end
    table.insert(h, { t = now, p = progress })
    while #h > 2 and now - h[1].t > HISTORY_MS do
        table.remove(h, 1)
    end
end

--- when (ms) the car with history h was at progress p, or nil
local function timeAt(h, p)
    if not h or #h < 2 or p < h[1].p or p > h[#h].p then
        return nil
    end
    local lo, hi = 1, #h
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if h[mid].p <= p then lo = mid else hi = mid end
    end
    local a, b = h[lo], h[hi]
    if b.p - a.p < 1e-6 then
        return a.t
    end
    return a.t + (b.t - a.t) * (p - a.p) / (b.p - a.p)
end

--- interval (ms) of `e` behind `ahead` at e's last checkpoint
local function exactInterval(mem, e, ahead)
    local mine = mem.crossings[e.playerID]
    local theirs = mem.crossings[ahead.playerID]
    if mine and theirs then
        local k = e.serverStep
        if k and mine[k] and theirs[k] then
            return mine[k] - theirs[k]
        end
    end
    return nil
end

---@param ctxt TickContext
T.get = function(ctxt)
    local race = getRace()
    if not race then
        cache.snapshot = nil
        return nil
    end
    if cache.now == ctxt.now and cache.snapshot then
        return cache.snapshot
    end
    cache.now = ctxt.now
    local recent = cache.snapshot
    if recent and recent.race == race and ctxt.now - cache.builtAt < SNAPSHOT_MS then
        local lapTimer = race.race.timers and race.race.timers.lap
        if recent.lapTime and lapTimer then
            recent.lapTime = lapTimer:get()
            if recent.expectedPbTime then
                recent.liveDelta = recent.lapTime - recent.expectedPbTime
            end
        end
        return recent
    end
    cache.builtAt = ctxt.now

    if not raceMemory or raceMemory.raceID ~= race.raceID or raceMemory.startTime ~= race.race.startTime then
        if raceMemory then
            RacePath.save(raceMemory.path)
        end
        raceMemory = newMemory(race)
    end
    local mem = raceMemory
    local path = mem.path
    local wpPerLap = mem.wpPerLap
    rememberLeaderboard(mem, race)
    local players = ctxt.players or {}
    local vehicles = raceVehicles(players)
    local selfID = (Platform.get("BJI_Context") or {}).User.playerID
    local laps = race.settings and race.settings.laps or 1
    local entries = {}
    local selfIndex

    for index, lb in ipairs(race.race.leaderboard or {}) do
        local isSelf = lb.playerID == selfID
        local lap = lb.lap or 1
        local wp = lb.wp or 0
        local serverStep = stepIndex(lap, wp, wpPerLap)
        if isSelf and not race.isFinished() then
            -- local values are ahead of the server's answer; race.race.waypoint
            -- counts checkpoints across all laps
            lap = race.race.lap or lap
            wp = math.max(0, math.min(wpPerLap, (race.race.waypoint or 0) - (lap - 1) * wpPerLap))
        end
        local e = {
            playerID = lb.playerID,
            name = players[lb.playerID] and players[lb.playerID].playerName or ("Player " .. tostring(lb.playerID)),
            position = index,
            lap = lap,
            wp = wp,
            diff = tonumber(lb.diff) or 0,
            time = tonumber(lb.time) or 0,
            finished = race.isFinished(lb.playerID),
            eliminated = race.isEliminated(lb.playerID),
            isSelf = isSelf,
            bestLap = mem.best[lb.playerID],
            lastLap = mem.last[lb.playerID],
            stepIndex = stepIndex(lap, wp, wpPerLap),
            serverStep = serverStep,
        }
        local obj = vehicles[lb.playerID]
        if obj and not e.finished and not e.eliminated then
            local pos = obj:getPosition()
            local p = { x = pos.x, y = pos.y, z = pos.z }
            e.progress = RacePath.progress(path, lap, wp, p)
            pushHistory(mem, lb.playerID, ctxt.now, e.progress)
            local vel = obj:getVelocity()
            e.speed = vel and vel:length() or 0
            if isSelf and race.isParticipant() then
                RacePath.record(path, lap, wp, p)
                if mem.ownLap ~= lap then
                    -- a lap completed: keep what was recorded
                    if mem.ownLap then
                        RacePath.save(path)
                    end
                    mem.ownLap = lap
                end
            end
        end
        if isSelf then
            selfIndex = index
        end
        table.insert(entries, e)
    end

    -- interval and distance to the car ahead for every entry
    for i, e in ipairs(entries) do
        local ahead = entries[i - 1]
        if ahead then
            local lapsDown = math.floor((ahead.stepIndex - e.stepIndex) / wpPerLap)
            if lapsDown >= 1 and not ahead.finished then
                e.intervalLaps = lapsDown
            else
                e.interval = exactInterval(mem, e, ahead) or (e.diff - ahead.diff)
            end
            if e.progress and ahead.progress then
                e.distanceAhead = ahead.progress - e.progress
                local tAhead = timeAt(mem.history[ahead.playerID], e.progress)
                if tAhead then
                    e.liveInterval = ctxt.now - tAhead
                end
            end
        end
    end

    local snapshot = {
        race = race,
        laps = laps,
        wpPerLap = wpPerLap,
        entries = entries,
        self = selfIndex and entries[selfIndex] or nil,
        ahead = selfIndex and entries[selfIndex - 1] or nil,
        behind = selfIndex and entries[selfIndex + 1] or nil,
        pathRecorded = RacePath.recordedCount(path),
    }

    -- own lap timing and delta to personal best
    local me = snapshot.self
    if me and race.isParticipant() and not me.finished and not me.eliminated then
        local lapTimer = race.race.timers and race.race.timers.lap
        snapshot.lapTime = lapTimer and lapTimer:get() or nil
        local pb = getPB(race.raceHash, ctxt.now)
        snapshot.bestLap = pb and pb[wpPerLap] and pb[wpPerLap].time or nil
        local w = me.wp
        local lapData = race.lapData or {}
        if pb and w > 0 and lapData[w] and pb[w] then
            snapshot.sectorDelta = lapData[w].time - pb[w].time
        end
        if pb and snapshot.lapTime and pb[w + 1] and me.progress then
            -- fraction of the current segment, along the race path
            local lapLen = RacePath.lapLength(path)
            local lapStart = (me.lap - 1) * lapLen
            local inLap = me.progress - lapStart
            local segStart, segEnd
            if mem.segBounds and mem.segBoundsVersion == path.version then
                segStart, segEnd = mem.segBounds[w], mem.segBounds[w + 1]
            end
            local frac = 0
            if segStart and segEnd and segEnd > segStart then
                frac = math.max(0, math.min(1, (inLap - segStart) / (segEnd - segStart)))
            end
            local prev = w > 0 and pb[w] and pb[w].time or 0
            local expected = prev + frac * (pb[w + 1].time - prev)
            snapshot.expectedPbTime = expected
            snapshot.liveDelta = snapshot.lapTime - expected
        end
        -- checkpoint distances along the path, for the live delta
        if mem.segBoundsVersion ~= path.version or not mem.segBounds then
            local bounds = { [0] = 0 }
            local lt = RacePath.lapLength(path)
            for k = 1, wpPerLap do
                local cp = path.cps[k]
                bounds[k] = cp and (RacePath.progress(path, 2, k, cp) - lt) or nil
            end
            mem.segBounds = bounds
            mem.segBoundsVersion = path.version
        end
    end

    if race.isFinished and race.isFinished() then
        RacePath.save(path)
    end

    -- gaps to the cars around me: exact (checkpoint) and live (path history)
    if snapshot.ahead and me then
        snapshot.gapAhead = {
            name = snapshot.ahead.name,
            interval = me.interval,
            laps = me.intervalLaps,
            distance = me.distanceAhead,
            live = me.liveInterval,
        }
    end
    if snapshot.behind and me then
        snapshot.gapBehind = {
            name = snapshot.behind.name,
            interval = snapshot.behind.interval,
            laps = snapshot.behind.intervalLaps,
            distance = snapshot.behind.distanceAhead,
            live = snapshot.behind.liveInterval,
        }
    end

    cache.snapshot = snapshot
    return snapshot
end

--- "+1.234" style seconds from ms
T.formatGap = function(ms)
    if not ms then
        return "--"
    end
    return string.format("%+.3f", ms / 1000)
end

T.formatLap = function(ms)
    if not ms then
        return "--:--.---"
    end
    return BJI.Utils.UI.RaceDelay(ms)
end

return T
