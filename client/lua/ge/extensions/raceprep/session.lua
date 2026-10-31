-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- Practice / qualifying sessions and track limits (game side).
--
-- Sessions: the server plugin announces a session (RacePrepSession: race,
-- checkpoints, time left, standings). While it runs and BeamJoy is in free
-- roam on the same map, this times the driver's own laps with
-- raceprep/lapTracker and sends each completed lap to the server.
--
-- Track limits: the vehicle extension raceprepLimits reports cuts (all
-- wheels off the track surface). In a session the lap in progress becomes
-- invalid. In a BeamJoy race (rule trackLimits not "off") the cut is sent
-- to the server, which relays it to every game for the results
-- (raceprep/results: invalid laps, penalties).
--
-- Grid: on a BeamJoy race grid, the driver's car PI is reported to the server
-- (handicap grids); that report also makes the server send the grid order.
--
-- Driven from bjiRacePrep.onUpdate.

local S = {}

local LapTracker = require("ge/extensions/raceprep/lapTracker")

S.data = nil     -- last session view from the server
S.laps = {}      -- my laps in this session, newest first
S.lastLap = nil  -- {time, valid, cuts, at (clock)}
S.cutFlashAt = nil

local tracker, trackerSession, trackerVeh
local deadline = nil -- fixed local expiry; signed server remaining survives overtime broadcasts
local receivedAt = 0 -- clock (s) when S.data arrived
local clockNow = 0
local nextLimitsSend = 0
local limitsOnVeh = nil
local nextGridReport, lastGridReport, lastGridAt = 0, nil, -1e9

local function log(level, msg)
    if type(_G.log) == "function" then _G.log(level, "bjiRacePrep", msg) end
end

local function flash(key, text, seconds)
    local msg = Platform.get("BJI_Message")
    if msg and msg.flash then pcall(msg.flash, key, text, seconds or 3, false) end
end

local function level()
    local fn = rawget(_G, "getCurrentLevelIdentifier")
    return fn and fn() or nil
end

local function scenarioState()
    local sc = Platform.get("BJI_Scenario")
    if not sc or not sc.TYPES then return "unknown" end
    if sc.isFreeroam and sc.isFreeroam() then return "freeroam" end
    local race = sc.TYPES.RACE_MULTI and sc.get(sc.TYPES.RACE_MULTI)
    if race and race.state then return "race", race end
    return "other"
end

local function ownVehicle()
    local vehicles = Platform.get("BJI_Veh")
    return vehicles and vehicles.getCurrentVehicleOwn and vehicles.getCurrentVehicleOwn() or nil
end

local function vehPos(veh)
    local p = veh and veh:getPosition()
    return p and { x = p.x, y = p.y, z = p.z } or nil
end

local function myRating(veh)
    local rt = rawget(_G, "raceprepRatings")
    if rt and rt.getVehicle and veh then
        local ok, entry = pcall(rt.getVehicle, veh:getID())
        if ok and type(entry) == "table" then return entry end
    end
end

local function send(event, payload)
    if (require("ge/extensions/raceprep/frontend").isCareer() or type(rawget(_G, "TriggerServerEvent")) == "function") then
        require('ge/extensions/raceprep/net').send(event, jsonEncode(payload))
    end
end

---------------------------------------------------------------- session state

--- the session is running (or in overtime) here: same map, free roam
S.active = function()
    local d = S.data
    return d and not d.native and (d.state == "running" or d.state == "overtime") and d.track and
        d.track.level == level() and scenarioState() == "freeroam" or false
end

-- Explain participation before the overlay decides what to show.
S.status = function()
    local d=S.data
    if not d then return {timing=false,code='none',message='No session is running.'} end
    if d.native then return {timing=false,code='native',message='BeamJoy is timing this phase. Join the weekend lobby and use the race HUD.'} end
    if d.state=='ended' then return {timing=false,code='ended',message='Session ended.'} end
    if not d.track or not d.track.level then return {timing=false,code='checkpoints',message='Session track/checkpoint data is missing.'} end
    if d.track.level~=level() then return {timing=false,code='map',message='This session is on another map ('..tostring(d.track.level)..').'} end
    if scenarioState()~='freeroam' then return {timing=false,code='freeroam',message='Return to free roam to participate in this session.'} end
    if not ownVehicle() then return {timing=false,code='vehicle',message='Choose your own car to start session timing.'} end
    if S.timingError or (tracker and trackerSession==d.id and not tracker:valid()) then
        return {timing=false,code='checkpoints',message='This session has no usable checkpoints; ask the host to check the race layout.'}
    end
    local native=d.track.nativeRace
    if (native and #(native.gates or {})<2) or (not native and #(d.track.steps or {})==0) then
        return {timing=false,code='checkpoints',message='This session has no usable checkpoints; ask the host to check the race layout.'}
    end
    return {timing=true,code='active',message='Cross the start/finish line to start timing.',
        sectorMessage=native and native.branchingEnabled and 'Branching layout: full laps are timed; separate sector splits are unavailable.' or nil}
end

--- ms left on the session clock (0 in overtime)
S.remaining = function()
    local d = S.data
    if not d then return 0 end
    return math.max(0, (d.remaining or 0) - (clockNow - receivedAt) * 1000)
end

-- the race weekend's step changes, shown as a short pill at the top centre
-- of the screen (raceprep/bjr/driving): {text, sub, at}
local WEEKEND_TEXT = {
    practice = function(w) return "Practice has started", w.practiceMinutes .. " min · " .. tostring(w.raceName) end,
    qualifying = function(w) return "Qualifying has started", w.qualifyingMinutes .. " min · your best lap sets your grid place" end,
    grid = function(w) return "Qualifying is over", "The grid is set · the race lobby opens next" end,
    race = function(w) return "Race", tostring(w.raceName) end,
}
S.ANNOUNCE_S = 6
S.weekend = function() return S.data and S.data.weekend or nil end

S.onSession = function(json)
    local ok, d = pcall(jsonDecode, json)
    if not ok or type(d) ~= "table" then return end
    local old = S.data
    local oldStage = old and old.weekend and old.weekend.stage
    local w = d.weekend
    if w and w.stage ~= oldStage and WEEKEND_TEXT[w.stage] then
        local text, sub = WEEKEND_TEXT[w.stage](w)
        S.announcement = { text = text, sub = sub, stage = w.stage, at = clockNow }
    end
    S.data = d
    receivedAt = clockNow
    if not old or old.id ~= d.id or d.state == "running" then
        deadline = clockNow + (d.deadlineRemaining or d.remaining or 0) / 1000
    end
    if not old or old.id ~= d.id then
        S.laps = {}
        S.lastLap = nil
        if d.state == "running" then
            flash("RacePrepSession", string.format("%s started: %s, %d min", d.label or "Session",
                tostring(d.raceName), d.minutes or 0), 5)
        end
    elseif old.state ~= d.state then
        if d.state == "overtime" then
            flash("RacePrepSession", "Time is up - finish your lap", 4)
        elseif d.state == "ended" then
            flash("RacePrepSession", (d.label or "Session") .. " over", 4)
        end
    end
    S.timingError=nil
    -- the window opens itself while a session is on (RaceSession.getState)
end

--- teleport my car to a free grid slot of the session's race
S.goToTrack = function()
    local d = S.data
    local veh = ownVehicle()
    local positions = d and d.track and d.track.startPositions
    if not S.active() then return false end
    if not veh or type(positions) ~= "table" or #positions == 0 then return false end
    local ctx = Platform.get("BJI_Context")
    local me = ctx and ctx.User and tonumber(ctx.User.playerID) or 0
    local slot = positions[(me % #positions) + 1]
    if type(slot) ~= "table" then return false end
    local function components(value, count)
        if type(value) ~= "string" then return value end
        local out = {}
        for token in value:gmatch("[^,%s]+") do
            local number = tonumber(token)
            if not number then return nil end
            out[#out+1] = number
        end
        if #out ~= count then return nil end
        return {x=out[1], y=out[2], z=out[3], w=out[4]}
    end
    local p, r = components(slot.pos, 3), components(slot.rot, 4)
    if Platform.isBJR() and p and slot.dir and beamjoy_vehicles and beamjoy_vehicles.setVehiclePositionRotation then
        local dir=components(slot.dir,3)
        if not dir then return false end
        local ok=pcall(beamjoy_vehicles.setVehiclePositionRotation,veh,vec3(p.x,p.y,p.z),vec3(dir.x,dir.y,dir.z),vec3(0,0,1),{cling=false,safe=false})
        tracker,trackerSession=nil,nil
        return ok
    end
    if not p or not r then return false end
    local vehicles = Platform.get("BJI_Veh")
    local ok = pcall(function()
        vehicles.setPositionRotation(vec3(p.x, p.y, p.z), quat(r.x, r.y, r.z, r.w), { safe = false })
    end)
    tracker, trackerSession = nil, nil -- teleport always starts a new out lap
    return ok
end

---------------------------------------------------------------- timing

local function onLap(lap, veh)
    if lap.incomplete then
        flash("RacePrepLap", "Lap not counted: checkpoint missed", 3)
        return
    end
    local d = S.data
    local endsAtClock = deadline or clockNow
    local lapStartClock = clockNow - lap.time / 1000
    local entry = myRating(veh)
    local sectors = tracker and tracker:sectorTimes(lap) or nil
    local payload = {
        sessionID = d.id, time = lap.time, valid = lap.valid, cuts = lap.cuts, sectors = sectors, distance = lap.distance,
        beforeEnd = lapStartClock < endsAtClock,
        model = veh and veh.getJBeamFilename and veh:getJBeamFilename() or nil,
        pi = entry and entry.pi or nil, class = entry and entry.class or nil,
    }
    send("RacePrepLap", payload)
    local rec = { time = lap.time, valid = lap.valid, cuts = lap.cuts, void = lap.void, sectors = sectors, at = clockNow }
    table.insert(S.laps, 1, rec)
    while #S.laps > 30 do table.remove(S.laps) end
    S.lastLap = rec
    local formatTime = require("ge/extensions/raceprep/results").formatTime
    if lap.valid then
        flash("RacePrepLap", "Lap " .. formatTime(lap.time), 3)
    else
        flash("RacePrepLap", "Lap " .. formatTime(lap.time) .. (lap.void and " - not counted (reset)" or
            string.format(" - invalid (track limits x%d)", lap.cuts)), 3)
    end
end

local function updateTiming(veh)
    if not S.active() or scenarioState() ~= "freeroam" or not veh then
        tracker, trackerSession = nil, nil
        return
    end
    local d = S.data
    if not tracker or trackerSession ~= d.id or trackerVeh ~= veh:getID() then
        tracker = d.track.nativeRace and require("ge/extensions/raceprep/bjr/lapTracker").new(d.track.nativeRace) or LapTracker.new(d.track.steps)
        trackerSession, trackerVeh = d.id, veh:getID()
        if not tracker:valid() then
            log("W", "Session track has no usable checkpoints")
        end
    end
    -- no new laps once the clock has run out (a lap in progress may finish)
    local lap = tracker:update(clockNow * 1000, vehPos(veh))
    if lap then
        onLap(lap, veh)
    end
    if d.state == "overtime" and tracker.state == "lap" then
        local endsAtClock = deadline or clockNow
        if tracker.lapStart / 1000 >= endsAtClock then
            tracker.state = "out" -- started after zero: does not count
        end
    end
end

--- ms into my current lap (session), or nil
S.currentLapTime = function()
    if tracker and tracker.state == "lap" then
        return tracker:current(clockNow * 1000)
    end
end

S.onTrackLap = function()
    return tracker and tracker.state == "lap" or false
end

S.currentLapCuts = function()
    return tracker and tracker.state == "lap" and tracker.cuts or 0
end

--- the lap in progress sector by sector, Forza style: each finished sector
--- against my best (green) and the session best (purple); delta = ms against
--- my best valid lap at the last finished sector. nil on the out-lap.
--- {sectors = {{n, ms?, mine?, session?, state = best|own|slower|live|next}}, delta?}
S.liveSectors = function()
    local t = tracker
    if not t or t.state ~= "lap" then return nil end
    local bounds = t.sectorBounds or t.bounds
    if type(bounds) ~= "table" or #bounds == 0 then return nil end
    local count = #bounds + 1
    local mine, bestLap = {}, nil
    for _, lap in ipairs(S.laps or {}) do
        if lap.valid and type(lap.sectors) == "table" and #lap.sectors == count then
            for i, v in ipairs(lap.sectors) do if not mine[i] or v < mine[i] then mine[i] = v end end
            if not bestLap or lap.time < bestLap.time then bestLap = lap end
        end
    end
    local session = {}
    for _, row in ipairs(S.data and S.data.rows or {}) do
        if type(row.bestSectors) == "table" and #row.bestSectors == count then
            for i, v in ipairs(row.bestSectors) do if not session[i] or v < session[i] then session[i] = v end end
        end
    end
    local out, prev, done, bestDone, live = {}, 0, 0, 0, false
    for i = 1, count do
        local e = { n = i, mine = mine[i], session = session[i] }
        local split = i < count and tonumber((t.splits or {})[bounds[i]]) or nil
        if split and not live then
            e.ms = split - prev
            prev, done = split, split
            if session[i] and e.ms <= session[i] then e.state = "best"
            elseif not mine[i] or e.ms <= mine[i] then e.state = "own"
            else e.state = "slower" end
            if bestLap then bestDone = bestDone + (bestLap.sectors[i] or 0) end
        elseif not live then
            e.state, live = "live", true
        else
            e.state = "next"
        end
        out[#out + 1] = e
    end
    return { sectors = out, delta = bestLap and done > 0 and (done - bestDone) or nil }
end

--- my track-limit cuts in the BJR race being run: {raceID, count, at}
S.raceCut = nil

---------------------------------------------------------------- track limits

local function raceTrackLimits(race)
    local rt = rawget(_G, "bjiRacePrep")
    local rules = rt and rt.getRules and rt.getRules(race and race.raceID) or {}
    return rules.trackLimits or "invalid"
end

local function racing(race)
    return race and race.STATES and race.state == race.STATES.RACE and race.isParticipant and race.isParticipant() and
        not (race.isFinished and race.isFinished()) and not (race.isEliminated and race.isEliminated()) and
        race.isRaceStarted and race.isRaceStarted()
end

local function disableLimits(id)
    local lookup = rawget(_G, "getObjectByID") or (rawget(_G, "be") and function(key) return be:getObjectByID(key) end)
    local old = lookup and lookup(id) or nil
    if old then old:queueLuaCommand("if raceprepLimits then raceprepLimits.disable() end") end
end

local function updateLimits(veh)
    local state, race = scenarioState()
    local rivals=package.loaded['ge/extensions/raceprep/bjr/rivalsSession']
    local want = (rivals and rivals.active() and (rivals.rules() or {}).trackLimits~='off') or (state == "freeroam" and S.active() and S.data.trackLimits ~= "off") or (state == "race" and racing(race) and raceTrackLimits(race) ~= "off")
    local id = veh and veh:getID()
    if not want then
        if limitsOnVeh then
            disableLimits(limitsOnVeh)
            limitsOnVeh = nil
        end
        return
    end
    if veh and (clockNow >= nextLimitsSend or limitsOnVeh ~= id) then
        nextLimitsSend = clockNow + 2 -- a reset reloads the vehicle extensions
        if limitsOnVeh and limitsOnVeh ~= id then disableLimits(limitsOnVeh) end
        limitsOnVeh = id
        veh:queueLuaCommand('extensions.load("raceprepLimits") if raceprepLimits then raceprepLimits.enable() end')
    end
end

--- called by the vehicle extension (through bjiRacePrep.onCut)
S.onCut = function(gameVehID)
    local veh = ownVehicle()
    if not veh or veh:getID() ~= gameVehID then return end
    local state, race = scenarioState()
    if state == "freeroam" and S.active() and S.data.trackLimits ~= "off" and tracker and tracker.state == "lap" then
        tracker:cut()
        S.cutFlashAt = clockNow
        flash("RacePrepCut", "Track limits - lap invalid", 2)
    elseif state == "race" and racing(race) then
        local mode = raceTrackLimits(race)
        if mode == "off" then return end
        local lap = race.race and race.race.lap or 1
        local rc = S.raceCut
        -- (raceprep/bjr/driving clears it when a new BJR race run starts)
        if not rc or rc.raceID ~= race.raceID then rc = { raceID = race.raceID, count = 0 } end
        rc.count, rc.at = rc.count + 1, clockNow
        S.raceCut = rc
        send("RacePrepCut", { raceID = race.raceID, lap = lap })
        S.cutFlashAt = clockNow
        flash("RacePrepCut", "Track limits - lap " .. tostring(lap) .. " invalid", 2)
    end
end

---------------------------------------------------------------- grid report

local function updateGridReport(veh)
    local state, race = scenarioState()
    if state ~= "race" or not race.STATES or race.state ~= race.STATES.GRID or
        not (race.isParticipant and race.isParticipant()) then
        lastGridReport = nil
        return
    end
    if clockNow < nextGridReport then return end
    nextGridReport = clockNow + 3
    local entry = myRating(veh)
    local key = tostring(race.raceID) .. ":" .. tostring(entry and entry.pi or 0)
    if key ~= lastGridReport or clockNow - lastGridAt >= 15 then
        lastGridReport, lastGridAt = key, clockNow
        local mp=veh and MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(veh:getID())
        send("RacePrepGridCar", { raceID = race.raceID, level = level(), pi = entry and entry.pi or 0, serverVehicleID=mp and mp.serverVehicleString })
    end
end

---------------------------------------------------------------- tick

S.update = function(clock)
    clockNow = clock
    local veh = ownVehicle()
    local ok, err = pcall(updateTiming, veh)
    S.timingError=not ok and tostring(err) or nil
    if not ok then log("E", "Session timing: " .. tostring(err)) end
    ok, err = pcall(updateLimits, veh)
    if not ok then log("E", "Track limits: " .. tostring(err)) end
    ok, err = pcall(updateGridReport, veh)
    if not ok then log("E", "Grid report: " .. tostring(err)) end
end

--- the announcement while it shows, else nil
S.currentAnnouncement = function()
    local a = S.announcement
    if a and clockNow - a.at <= S.ANNOUNCE_S then return a end
end

--- race weekend controls (sent to the server; it checks the permission)
S.weekendStart = function(raceID, practiceMinutes, qualifyingMinutes, gridOrder, raceLaps)
    send("RacePrepWeekendStart", { raceID = raceID, level = level(), practiceMinutes = practiceMinutes,
        qualifyingMinutes = qualifyingMinutes, raceLaps = raceLaps, gridOrder = gridOrder })
end
S.weekendNext = function() send("RacePrepWeekendNext", {}) end
S.weekendEnd = function() send("RacePrepWeekendEnd", {}) end

S.isMine = function(playerID)
    local ctx = Platform.get("BJI_Context")
    return ctx and ctx.User and ctx.User.playerID == playerID
end

return S
